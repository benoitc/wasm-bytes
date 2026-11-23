%% Runs one recorded reply in two engines, erlang_wasm and Wasmtime, on the
%% task's inputs, and compares both with the task's reference answers.
%%
%% Each engine's side hashes the bytes it was handed: erlang_wasm the bytes
%% passed to `wasm:compile/1', Wasmtime the file read back from disk. A
%% report therefore says which bytes each engine received, not only which
%% file was named.
-module(wb_compare).

-export([compare/3, report/1, record/2, summarize/1]).

-export_type([comparison/0]).

-type outcome() :: {ok, integer()} | {error, binary()} | {rejected, atom()}.
-type comparison() :: #{atom() => term()}.

-spec compare(wb_task:name(), binary(), binary()) ->
          {ok, comparison()} | {error, wasmtime_not_found | {malformed_hex, term()}}.
compare(Task, Text, ReplyName) ->
    case {wb_wasmtime:find(), wb_hex:decode(Text)} of
        {{error, not_found}, _} -> {error, wasmtime_not_found};
        {_, {error, Why}} -> {error, {malformed_hex, Why}};
        {{ok, Exe}, {ok, Bytes}} -> {ok, run(Task, Text, Bytes, Exe, ReplyName)}
    end.

run(Task, Text, Bytes, Exe, ReplyName) ->
    Inputs = wb_task:inputs(Task),
    #{export := Export} = wb_task:get(Task),
    Check = wb_check:check(Task, Text),
    Erlang = erlang_outcomes(Check, Inputs),
    Dir = temp_dir(),
    Wasm = filename:join(Dir, "module.wasm"),
    ok = file:write_file(Wasm, Bytes),
    {ok, OnDisk} = file:read_file(Wasm),
    Wasmtime = try wb_wasmtime:run(Exe, Wasm, Export, Inputs)
               after file:del_dir_r(Dir)
               end,
    Rows = [{X, wb_task:expected(Task, X), E, W}
            || {{X, E}, {X, W}} <- lists:zip(Erlang, Wasmtime)],
    #{erlang_matches := ErlMatches, wasmtime_matches := WtMatches} = S = summarize(Rows),
    #{task => Task,
      reply => ReplyName,
      module_bytes => byte_size(Bytes),
      module_sha256 => sha256(Bytes),
      inputs => length(Inputs),
      erlang_wasm => #{version => vsn(wasm), verdict => maps:get(verdict, Check),
                       received_sha256 => sha256(maps:get(bytes, Check, <<>>)),
                       matches => ErlMatches},
      wasmtime => #{version => wb_wasmtime:version(Exe),
                    received_sha256 => sha256(OnDisk),
                    matches => WtMatches},
      agree => maps:get(agree, S),
      first_discrepancy => maps:get(first_discrepancy, S),
      verdict => maps:get(verdict, S),
      host => wb_host:info(),
      recorded_on => today()}.

%% What erlang_wasm answered for each input, through the same checker the
%% rest of the runner uses. A module it refused before running is `rejected'
%% on every input.
erlang_outcomes(#{results := Results}, Inputs) when length(Results) =:= length(Inputs) ->
    [{X, case O of
             {ok, V} -> {ok, V};
             {error, #{class := C, kind := K}} -> {error, iolist_to_binary([atom_to_list(C), "/", atom_to_list(K)])};
             {error, _} -> {error, ~"error"};
             not_run -> {error, ~"not run"}
         end} || {X, O} <- Results];
erlang_outcomes(#{verdict := V}, Inputs) ->
    [{X, {rejected, V}} || X <- Inputs].

%% The scoring, apart from running anything: `Rows' are
%% `{Input, Reference, ErlangWasm, Wasmtime}'.
-spec summarize([{integer(), integer(), outcome(), outcome()}]) -> map().
summarize(Rows) ->
    Total = length(Rows),
    ErlMatches = length([X || {X, R, {ok, R}, _} <- Rows]),
    WtMatches = length([X || {X, R, _, {ok, R}} <- Rows]),
    #{erlang_matches => ErlMatches,
      wasmtime_matches => WtMatches,
      agree => length([Row || {_, _, E, W} = Row <- Rows, agree(E, W)]),
      first_discrepancy => first_discrepancy(Rows),
      verdict => verdict(Rows, Total, ErlMatches, WtMatches)}.

%% `pass': both engines give the reference answer on every input.
%% `engines_differ': on some input the two engines do not agree.
%% `reference_differs': they agree everywhere, and not with the reference.
verdict(_Rows, Total, Total, Total) -> pass;
verdict(Rows, _Total, _, _) ->
    case lists:all(fun({_, _, E, W}) -> agree(E, W) end, Rows) of
        true -> reference_differs;
        false -> engines_differ
    end.

%% Both returned the same value, or both failed to return one. The reasons a
%% call fails are worded differently by each engine and are not compared.
agree({ok, V}, {ok, V}) -> true;
agree({ok, _}, _) -> false;
agree(_, {ok, _}) -> false;
agree(_, _) -> true.

first_discrepancy(Rows) ->
    case [Row || {_, R, E, W} = Row <- Rows,
                 E =/= {ok, R} orelse W =/= {ok, R} orelse not agree(E, W)] of
        [] -> none;
        [{X, R, E, W} | _] -> #{input => X, reference => R, erlang_wasm => E, wasmtime => W}
    end.

-spec report(comparison()) -> iodata().
report(#{module_sha256 := Hash, erlang_wasm := Erl, wasmtime := Wt, inputs := Total} = C) ->
    [line("reply", maps:get(reply, C)),
     line("module", io_lib:format("~b bytes, sha256 ~ts", [maps:get(module_bytes, C), Hash])),
     line("host", wb_host:describe(maps:get(host, C))),
     line("inputs", io_lib:format("~b, each compared with the ~ts task's reference answer",
                                  [Total, maps:get(task, C)])),
     line("erlang_wasm", engine(Erl, Hash, Total)),
     line("wasmtime", engine(Wt, Hash, Total)),
     line("agree", io_lib:format("~b of ~b inputs give the same result in both engines",
                                 [maps:get(agree, C), Total])),
     line("first diff", discrepancy(maps:get(first_discrepancy, C))),
     line("verdict", atom_to_list(maps:get(verdict, C)))].

engine(#{version := V, received_sha256 := Got, matches := M} = E, Hash, Total) ->
    [V, ", ",
     case Got of
         Hash -> "received the same bytes";
         _ -> ["received DIFFERENT bytes, sha256 ", Got]
     end,
     case E of
         #{verdict := Verdict} when Verdict =/= pass, M =:= 0 ->
             io_lib:format("; checker verdict ~p", [Verdict]);
         _ -> []
     end,
     io_lib:format(": ~b of ~b match the reference", [M, Total])].

discrepancy(none) ->
    "none";
discrepancy(#{input := X, reference := R, erlang_wasm := E, wasmtime := W}) ->
    io_lib:format("input ~b: reference ~b, erlang_wasm ~ts, wasmtime ~ts",
                  [X, R, outcome(E), outcome(W)]).

-spec outcome(outcome()) -> iodata().
outcome({ok, V}) -> integer_to_list(V);
outcome({error, Why}) -> ["error (", Why, ")"];
outcome({rejected, V}) -> ["rejected (", atom_to_list(V), ")"].

%% Writes `Dir/<task>-<label>/<os>-<arch>.config' for a reply under
%% `trials/' or `examples/', so that runs of different replies on one host
%% do not overwrite each other, and returns its path.
-spec record(comparison(), file:filename()) -> file:filename().
record(C, Dir) ->
    Slug = binary_to_list(wb_host:slug(maps:get(host, C))),
    Path = filename:join([Dir, record_name(maps:get(reply, C)), Slug ++ ".config"]),
    Keys = [recorded_on, reply, task, module_bytes, module_sha256, host, inputs,
            erlang_wasm, wasmtime, agree, first_discrepancy, verdict],
    Terms = [io_lib:format("~tp.~n", [{K, maps:get(K, C)}]) || K <- Keys],
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, ["%% Written by bin/wasm-bytes compare --record.\n" | Terms]),
    Path.

record_name(Reply) ->
    case filename:split(unicode:characters_to_list(Reply)) of
        [Kind, Task, Label, "reply.txt"] when Kind =:= "trials"; Kind =:= "examples" ->
            Task ++ "-" ++ Label;
        Parts ->
            filename:rootname(lists:last(Parts))
    end.

line(Tag, Text) ->
    [io_lib:format("  ~-12s ", [Tag]), Text, $\n].

sha256(Bin) ->
    binary:encode_hex(crypto:hash(sha256, Bin), lowercase).

vsn(App) ->
    case application:get_key(App, vsn) of
        {ok, V} -> list_to_binary(V);
        undefined -> ~"unknown"
    end.

today() ->
    {{Y, M, D}, _} = calendar:local_time(),
    iolist_to_binary(io_lib:format("~4..0b-~2..0b-~2..0b", [Y, M, D])).

temp_dir() ->
    Base = case os:getenv("TMPDIR") of
               T when is_list(T), T =/= "" -> T;
               _ -> "/tmp"
           end,
    Dir = filename:join(Base, "wasm-bytes-" ++ integer_to_list(erlang:unique_integer([positive]))
                              ++ "-" ++ os:getpid()),
    ok = file:make_dir(Dir),
    Dir.
