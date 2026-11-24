%% The WasmBench track: reading cases from real-world binaries.
%%
%% The source is WasmBench's filtered dataset, release v1.0: 8,461 binaries
%% collected from websites, GitHub, NPM and other places, each named by its
%% SHA-256, with metadata saying where it was found. A reading case asks what
%% one exported function returns for one call. No expected answer is written
%% by hand: the runner calls the binary, in the same fresh, fuel-limited
%% instance as any reply, and records what it returns.
%%
%% A binary is skipped, with its reason counted, when it is too large to show
%% in a prompt, does not match its name, does not decode or validate in
%% erlang_wasm, imports anything (the runner provides nothing), exports no
%% function of up to two i32 arguments returning one i32, or has no such call
%% that returns, and returns the same value twice.
%%
%% The binaries are not this project's. A case is written for the sample
%% kept in the repository only when a source it was collected from has an
%% open license, which `licenses' gives; a corpus run writes cases for every
%% usable binary under `_build/'.
-module(wb_wasmbench).

-export([prepare/2, examine/3, candidate_args/3, archive/0, open_license/1]).

-define(ARCHIVE, "https://github.com/sola-st/WasmBench/releases/download/v1.0/filtered-binaries-metadata.7z").
-define(ARCHIVE_SHA256, "2dffbe0120ad5857734ba6ac16b2c789f2fe2f9dda814e0168b6faccf79b58fe").
-define(MAX_BYTES, 2048).
%% Argument sets tried per export, in seeded order, until one call returns.
-define(TRIES, 4).

-spec archive() -> map().
archive() ->
    #{url => ?ARCHIVE, sha256 => ?ARCHIVE_SHA256, max_bytes => ?MAX_BYTES}.

%% `From' is the unpacked archive: `filtered/<sha256>.wasm' and
%% `filtered.pretty.json'. `sample' is `all' for a corpus run, or how many
%% openly licensed cases to keep; `licenses' maps a GitHub repository,
%% `<<"owner/name">>', to its SPDX license id.
-spec prepare(file:filename(), map()) -> {ok, map()}.
prepare(From, #{out := Out, seed := Seed, sample := Sample} = Opts) ->
    Licenses = maps:get(licenses, Opts, #{}),
    {ok, Json} = file:read_file(filename:join(From, "filtered.pretty.json")),
    Meta = json:decode(Json),
    Names = lists:sort(filelib:wildcard("*.wasm", filename:join(From, "filtered"))),
    Results = [examine(filename:join([From, "filtered", N]), Seed, Meta) || N <- Names],
    Usable = [U || {usable, _} = U <- Results],
    Skipped = [R || {skipped, R} <- Results],
    Order = wb_spec:order(Seed, [Hash || {usable, #{sha256 := Hash}} <- Usable]),
    ByHash = maps:from_list([{Hash, U} || {usable, #{sha256 := Hash} = U} <- Usable]),
    Chosen = case Sample of
                 all -> [maps:get(H, ByHash) || H <- Order];
                 N -> lists:sublist([U || H <- Order,
                                          U <- [maps:get(H, ByHash)],
                                          licensed(U, Licenses) =/= none], N)
             end,
    Dir = filename:join(Out, "wasmbench"),
    _ = file:del_dir_r(Dir),
    Ids = [write_case(Dir, U, Licenses) || U <- Chosen],
    Selection = [{source, <<?ARCHIVE>>}, {archive_sha256, <<?ARCHIVE_SHA256>>},
                 {seed, Seed}, {max_bytes, ?MAX_BYTES},
                 {examined, length(Results)},
                 {usable, length(Usable)},
                 {skipped, count(Skipped)},
                 {sample, case Sample of all -> all; _ -> <<"openly licensed only">> end},
                 {read, Ids}],
    ok = wb_terms:write(filename:join(Dir, "selection.config"),
                        "Written by bin/wasm-bytes prepare wasmbench. Every binary in the archive "
                        "is examined once; a usable one has a call that returns.", Selection),
    {ok, maps:from_list(Selection)}.

count(Reasons) ->
    [{R, length([x || R1 <- Reasons, R1 =:= R])} || R <- lists:usort(Reasons)].

%% One binary: `{usable, Info}' with the call to ask about, or
%% `{skipped, Reason}'.
-spec examine(file:filename(), integer(), map()) -> {usable, map()} | {skipped, binary()}.
examine(Path, Seed, Meta) ->
    Hash = list_to_binary(filename:basename(Path, ".wasm")),
    case filelib:file_size(Path) of
        Size when Size > ?MAX_BYTES ->
            {skipped, <<"larger than 2048 bytes, too long to show in a prompt">>};
        _ ->
            {ok, Bytes} = file:read_file(Path),
            case sha256(Bytes) of
                Hash -> decoded(Hash, Bytes, Seed, maps:get(Hash, Meta, #{}));
                _ -> {skipped, <<"its SHA-256 does not match its name">>}
            end
    end.

decoded(Hash, Bytes, Seed, Meta) ->
    case wasm:compile(Bytes) of
        {error, #{class := malformed}} -> {skipped, <<"erlang_wasm cannot decode it">>};
        {error, #{class := invalid}} -> {skipped, <<"it fails validation in erlang_wasm">>};
        {error, _} -> {skipped, <<"erlang_wasm does not support it">>};
        {ok, Module} -> profile(Hash, Bytes, Module, Seed, Meta)
    end.

profile(Hash, Bytes, Module, Seed, Meta) ->
    {ok, Sections} = wb_layout:sections(Bytes),
    Imports = lists:sum([wb_layout:count(Bytes, S) || S <- wb_layout:find(2, Sections)]),
    Exports = [Name || S <- wb_layout:find(7, Sections),
                       {Name, func, _} <- wb_layout:exports(Bytes, S)],
    Integer = [{Name, Ps} || Name <- lists:usort(Exports),
                             {ok, {Ps, [i32]}} <- [wasm:func_type_of(Bytes, Name)],
                             length(Ps) =< 2, lists:all(fun(P) -> P =:= i32 end, Ps)],
    if
        Imports > 0 -> {skipped, <<"it imports something, and the runner provides nothing">>};
        Integer =:= [] -> {skipped, <<"no exported function takes up to two i32 arguments and returns one i32">>};
        true -> first_call(Hash, Bytes, Module, Seed, Meta, Integer)
    end.

%% The exports in seeded order; for each, the argument sets in seeded order,
%% until a call returns the same value twice.
first_call(Hash, Bytes, Module, Seed, Meta, Exports) ->
    Order = wb_spec:order(Seed, [<<Hash/binary, ":", N/binary>> || {N, _} <- Exports]),
    Tried = [{N, Args, call(Module, N, Args)}
             || Key <- Order,
                {N, Ps} <- [lists:keyfind(binary:part(Key, 65, byte_size(Key) - 65), 1, Exports)],
                Args <- candidate_args(Seed, <<Hash/binary, ":", N/binary>>, length(Ps))],
    case [{N, Args, V} || {N, Args, {ok, V}} <- Tried] of
        [{N, Args, V} | _] ->
            {usable, #{sha256 => Hash, bytes => Bytes, export => N, call => Args,
                       expected => V, params => length(Args), meta => Meta}};
        [] ->
            case [instantiate || {_, _, {error, instantiate}} <- Tried] of
                [_ | _] -> {skipped, <<"it cannot be instantiated within the runner's limits">>};
                [] -> {skipped, <<"no call returned within the runner's limits">>}
            end
    end.

%% Twice, each in a fresh instance: a call whose answer could change from one
%% run to the next cannot be predicted.
call(Module, Export, Args) ->
    case {run(Module, Export, Args), run(Module, Export, Args)} of
        {{ok, V}, {ok, V}} -> {ok, V};
        {{error, instantiate}, _} -> {error, instantiate};
        _ -> {error, no_answer}
    end.

run(Module, Export, Args) ->
    case wb_exec:run(Module, Export, [Args]) of
        {ok, [{_, {ok, V}}]} -> {ok, V};
        {ok, _} -> {error, no_answer};
        {error, {instantiate, _}} -> {error, instantiate}
    end.

%% Up to `?TRIES' argument sets for a function of `Arity' i32 arguments,
%% chosen by the seed from small and boundary values.
-spec candidate_args(integer(), binary(), 0..2) -> [[integer()]].
candidate_args(_Seed, _Key, 0) ->
    [[]];
candidate_args(Seed, Key, Arity) ->
    Values = [0, 1, 2, 3, 5, 7, 10, 12, 42, 100, 255, 1000, -1, -7, 65535, 2147483647, -2147483648],
    Sets = case Arity of
               1 -> [[A] || A <- Values];
               2 -> [[A, B] || A <- Values, B <- Values]
           end,
    Keyed = maps:from_list([{<<Key/binary, ":", (iolist_to_binary(io_lib:format("~w", [S])))/binary>>, S}
                            || S <- Sets]),
    [maps:get(K, Keyed) || K <- lists:sublist(wb_spec:order(Seed, maps:keys(Keyed)), ?TRIES)].

%% The open license of a source the binary was collected from, if any.
licensed(#{meta := Meta}, Licenses) ->
    Repos = [R || #{<<"repository">> := R} <- maps:get(<<"files">>, Meta, [])],
    case [{R, L} || R <- Repos, L <- [maps:get(R, Licenses, none)], open_license(L)] of
        [First | _] -> First;
        [] -> none
    end.

-spec open_license(term()) -> boolean().
open_license(L) ->
    lists:member(L, [<<"MIT">>, <<"Apache-2.0">>, <<"BSD-2-Clause">>, <<"BSD-3-Clause">>,
                     <<"ISC">>, <<"MPL-2.0">>, <<"Unlicense">>, <<"CC0-1.0">>, <<"Zlib">>,
                     <<"0BSD">>, <<"BSL-1.0">>]).

write_case(Dir, #{sha256 := Hash, bytes := Bytes, export := Export, call := Args,
                  expected := V, meta := Meta} = U, Licenses) ->
    Name = <<(binary:part(Hash, 0, 12))/binary, "-", (dir_safe(Export))/binary>>,
    CaseDir = filename:join([Dir, "read", Name]),
    ok = filelib:ensure_path(CaseDir),
    ok = file:write_file(filename:join(CaseDir, "module.wasm"), Bytes),
    Origins = [iolist_to_binary([maps:get(<<"collection_method">>, F, <<"?">>), ": ",
                                 maps:get(<<"repository">>, F, <<>>),
                                 case maps:get(<<"repository">>, F, <<>>) of <<>> -> <<>>; _ -> <<" ">> end,
                                 maps:get(<<"filename">>, F, <<>>)])
               || F <- maps:get(<<"files">>, Meta, [])],
    License = case licensed(U, Licenses) of
                  {Repo, L} -> [{license, <<L/binary, " (", Repo/binary, ")">>}];
                  none -> []
              end,
    ok = wb_terms:write(filename:join(CaseDir, "case.config"),
                        "A reading case from WasmBench. The module is the binary as the dataset "
                        "has it; the expected value is what it returned when the runner called it.",
                        [{export, Export}, {params, lists:duplicate(length(Args), i32)},
                         {results, [i32]}, {call, Args}, {expected, V},
                         {module_sha256, Hash},
                         {upstream, [{dataset, <<"WasmBench v1.0, filtered">>},
                                     {archive, <<?ARCHIVE>>},
                                     {sha256, Hash},
                                     {origins, Origins} | License]}]),
    Name.

dir_safe(Export) ->
    re:replace(Export, "[^A-Za-z0-9_.-]", "_", [global, {return, binary}]).

sha256(Bin) ->
    binary:encode_hex(crypto:hash(sha256, Bin), lowercase).
