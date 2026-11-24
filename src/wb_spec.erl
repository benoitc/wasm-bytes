%% The spec-test track: cases from the official WebAssembly test suite.
%%
%% The source is `i32.wast' from WebAssembly/testsuite at a pinned commit,
%% kept in `datasets/spec/'. Its first module exports one function per i32
%% instruction, and each `assert_return' after it gives a call and its result.
%% Those assertions are the expected answers; nothing here computes one.
%%
%%   read   one assertion: the module shows a function that applies the
%%          instruction, the model predicts the result of the asserted call
%%   write  one instruction: the model writes the module from an English
%%          description, and every assertion for that instruction checks it
%%
%% `assert_trap' has no value to predict, so it is counted and skipped.
-module(wb_spec).

-export([prepare/2, source/0, ops/0, assertions/1, order/2]).

-define(REPO, "https://github.com/WebAssembly/testsuite").
-define(COMMIT, "92a3d806c7d70f5b63f125e6155b8d76304509f1").
-define(WAST, "i32.wast").
-define(LOCAL, "datasets/spec/i32.wast").
-define(SHA256, "f3b7e8fd641893ea0989a8ab801fce0654d276d27b5cad9cf482291a422cffe8").

%% The example in doc/datasets.md: 32-bit addition, in both directions.
-define(EXAMPLE_READ, <<"add-41">>).
-define(EXAMPLE_WRITE, <<"add">>).

-spec source() -> map().
source() ->
    #{repo => ?REPO, commit => ?COMMIT, file => ?WAST, local => ?LOCAL, sha256 => ?SHA256}.

%% Each selected instruction: its export in `i32.wast', its opcode, how many
%% arguments it takes, and what a writing prompt says it does. The wording
%% states the behavior, including the edge cases the assertions test.
-spec ops() -> [{binary(), byte(), 1 | 2, string()}].
ops() ->
    [{<<"add">>, 16#6a, 2, "It adds its two arguments, wrapping on 32-bit overflow."},
     {<<"sub">>, 16#6b, 2, "It subtracts its second argument from its first, wrapping on 32-bit overflow."},
     {<<"mul">>, 16#6c, 2, "It multiplies its two arguments and returns the low 32 bits of the product."},
     {<<"div_s">>, 16#6d, 2, "It divides its first argument by its second as signed integers, rounding toward zero."},
     {<<"div_u">>, 16#6e, 2, "It divides its first argument by its second, both read as unsigned 32-bit integers, and returns the quotient."},
     {<<"rem_s">>, 16#6f, 2, "It returns the remainder of dividing its first argument by its second as signed integers; the remainder has the sign of the first argument."},
     {<<"rem_u">>, 16#70, 2, "It returns the remainder of dividing its first argument by its second, both read as unsigned 32-bit integers."},
     {<<"and">>, 16#71, 2, "It returns the bitwise AND of its two arguments."},
     {<<"or">>, 16#72, 2, "It returns the bitwise OR of its two arguments."},
     {<<"xor">>, 16#73, 2, "It returns the bitwise exclusive OR of its two arguments."},
     {<<"shl">>, 16#74, 2, "It shifts its first argument left by its second argument taken modulo 32, filling with zero bits."},
     {<<"shr_s">>, 16#75, 2, "It shifts its first argument right by its second argument taken modulo 32, copying the sign bit into the bits it vacates."},
     {<<"shr_u">>, 16#76, 2, "It shifts its first argument right by its second argument taken modulo 32, filling with zero bits."},
     {<<"rotl">>, 16#77, 2, "It rotates the 32 bits of its first argument left by its second argument taken modulo 32."},
     {<<"rotr">>, 16#78, 2, "It rotates the 32 bits of its first argument right by its second argument taken modulo 32."},
     {<<"clz">>, 16#67, 1, "It returns the number of leading zero bits in its argument, which is 32 for zero."},
     {<<"ctz">>, 16#68, 1, "It returns the number of trailing zero bits in its argument, which is 32 for zero."},
     {<<"popcnt">>, 16#69, 1, "It returns the number of bits set to 1 in its argument."},
     {<<"extend8_s">>, 16#c0, 1, "It returns the low 8 bits of its argument, read as a signed 8-bit integer."},
     {<<"extend16_s">>, 16#c1, 1, "It returns the low 16 bits of its argument, read as a signed 16-bit integer."},
     {<<"eqz">>, 16#45, 1, "It returns 1 if its argument is zero, and 0 otherwise."},
     {<<"eq">>, 16#46, 2, "It returns 1 if its two arguments are equal, and 0 otherwise."},
     {<<"ne">>, 16#47, 2, "It returns 1 if its two arguments differ, and 0 otherwise."},
     {<<"lt_s">>, 16#48, 2, "It returns 1 if its first argument is less than its second as signed integers, and 0 otherwise."},
     {<<"lt_u">>, 16#49, 2, "It returns 1 if its first argument is less than its second as unsigned 32-bit integers, and 0 otherwise."},
     {<<"gt_s">>, 16#4a, 2, "It returns 1 if its first argument is greater than its second as signed integers, and 0 otherwise."},
     {<<"gt_u">>, 16#4b, 2, "It returns 1 if its first argument is greater than its second as unsigned 32-bit integers, and 0 otherwise."},
     {<<"le_s">>, 16#4c, 2, "It returns 1 if its first argument is less than or equal to its second as signed integers, and 0 otherwise."},
     {<<"le_u">>, 16#4d, 2, "It returns 1 if its first argument is less than or equal to its second as unsigned 32-bit integers, and 0 otherwise."},
     {<<"ge_s">>, 16#4e, 2, "It returns 1 if its first argument is greater than or equal to its second as signed integers, and 0 otherwise."},
     {<<"ge_u">>, 16#4f, 2, "It returns 1 if its first argument is greater than or equal to its second as unsigned 32-bit integers, and 0 otherwise."}].

%% The assertions about the first module of `Source', a `.wast' text:
%% `{usable, Op, Args, Expected, Line}' for an `assert_return' on a selected
%% instruction, and `{skipped, Reason, Line}' for anything else asserted
%% about it. Assertions after a second module are about that module.
-spec assertions(binary()) -> [tuple()].
assertions(Source) ->
    {ok, Commands} = wasm_wast:script(Source),
    first_module(Commands, 0, []).

first_module([], _Modules, Acc) ->
    lists:reverse(Acc);
first_module([#{<<"type">> := <<"module">>} | _], 1, Acc) ->
    lists:reverse(Acc);
first_module([#{<<"type">> := <<"module">>} | Rest], 0, Acc) ->
    first_module(Rest, 1, Acc);
first_module([C | Rest], 1, Acc) ->
    first_module(Rest, 1, [classify(C) || is_assertion(C)] ++ Acc);
first_module([_ | Rest], M, Acc) ->
    first_module(Rest, M, Acc).

is_assertion(#{<<"type">> := T}) ->
    lists:member(T, [<<"assert_return">>, <<"assert_trap">>, <<"assert_exhaustion">>]).

classify(#{<<"type">> := <<"assert_return">>, <<"line">> := Line,
           <<"action">> := #{<<"type">> := <<"invoke">>, <<"field">> := Op, <<"args">> := Args},
           <<"expected">> := [#{<<"type">> := <<"i32">>, <<"value">> := V}]}) ->
    case {lists:keymember(Op, 1, ops()), [A || #{<<"type">> := T} = A <- Args, T =/= <<"i32">>]} of
        {true, []} ->
            {usable, Op, [binary_to_integer(maps:get(<<"value">>, A)) || A <- Args],
             binary_to_integer(V), Line};
        {false, _} -> {skipped, "the instruction is not in the selection", Line};
        {true, _} -> {skipped, "an argument is not an i32", Line}
    end;
classify(#{<<"type">> := <<"assert_trap">>, <<"line">> := Line}) ->
    {skipped, "the call traps, so there is no value to predict", Line};
classify(#{<<"line">> := Line}) ->
    {skipped, "not a call with one i32 result", Line}.

%% The order a selection takes items in: by the SHA-256 of `"<seed>:<id>"',
%% which anyone can recompute without this code.
-spec order(integer(), [binary()]) -> [binary()].
order(Seed, Ids) ->
    Key = fun(Id) -> crypto:hash(sha256, [integer_to_binary(Seed), ":", Id]) end,
    [Id || {_, Id} <- lists:sort([{Key(Id), Id} || Id <- Ids])].

%% Writes the track's cases to `<Out>/spec/', replacing what is there, and
%% returns the selection. `read' and `write' are how many cases of each to
%% keep (`all' for the whole source); the walkthrough's two cases are always
%% kept, then the rest follow the seeded order.
-spec prepare(file:filename(), #{out := file:filename(), seed := integer(),
                                 read := pos_integer() | all, write := pos_integer() | all}) ->
          {ok, map()} | {error, term()}.
prepare(Root, #{out := Out, seed := Seed, read := NRead, write := NWrite}) ->
    {ok, Source} = file:read_file(filename:join(Root, ?LOCAL)),
    case sha256(Source) of
        <<?SHA256>> -> prepare_from(Source, Out, Seed, NRead, NWrite);
        Other -> {error, {source_changed, ?LOCAL, Other}}
    end.

prepare_from(Source, Out, Seed, NRead, NWrite) ->
    All = assertions(Source),
    Usable0 = [A || {usable, _, _, _, _} = A <- All],
    %% Each assertion is replayed against the module the reading case shows,
    %% so a case can never expect what that module does not return.
    {Usable, Disagree} = lists:partition(fun agrees/1, Usable0),
    Skipped = [{R, L} || {skipped, R, L} <- All] ++
              [{"the reference module returns something else", L} || {usable, _, _, _, L} <- Disagree],
    ReadIds = [read_name(A) || A <- Usable],
    WriteIds = lists:usort([Op || {usable, Op, _, _, _} <- Usable]),
    Read = pick(Seed, NRead, ?EXAMPLE_READ, ReadIds),
    Write = pick(Seed, NWrite, ?EXAMPLE_WRITE, WriteIds),
    Dir = filename:join(Out, "spec"),
    _ = file:del_dir_r(Dir),
    [write_read_case(Dir, A) || A <- Usable, lists:member(read_name(A), Read)],
    [write_write_case(Dir, Op, [A || {usable, O, _, _, _} = A <- Usable, O =:= Op]) || Op <- Write],
    Selection = [{source, <<?REPO>>}, {commit, <<?COMMIT>>}, {file, <<?WAST>>}, {file_sha256, <<?SHA256>>},
                 {seed, Seed},
                 {examined, length(All)},
                 {usable, length(Usable)},
                 {skipped, [{unicode:characters_to_binary(R), N} || {R, N} <- count_reasons(Skipped)]},
                 {read, Read},
                 {write, Write}],
    ok = write_terms(filename:join(Dir, "selection.config"),
                     "Written by bin/wasm-bytes prepare spec. Each assertion in the first module "
                     "of the source is examined once.", Selection),
    {ok, maps:from_list(Selection)}.

agrees({usable, Op, Args, Want, _Line}) ->
    {Op, Opcode, Arity, _} = lists:keyfind(Op, 1, ops()),
    length(Args) =:= Arity andalso
        begin
            {ok, M} = wasm:compile(wb_encode:op_module(Arity, Opcode)),
            {ok, [{_, Got}]} = wb_exec:run(M, <<"f">>, [Args]),
            Got =:= {ok, Want}
        end.

read_name({usable, Op, _Args, _Want, Line}) ->
    <<Op/binary, "-", (integer_to_binary(Line))/binary>>.

pick(Seed, all, Example, Ids) ->
    [Example | [Id || Id <- order(Seed, Ids), Id =/= Example]];
pick(Seed, N, Example, Ids) ->
    lists:sublist([Example | [Id || Id <- order(Seed, Ids), Id =/= Example]], N).

count_reasons(Skipped) ->
    Reasons = lists:usort([R || {R, _} <- Skipped]),
    [{R, length([x || {R1, _} <- Skipped, R1 =:= R])} || R <- Reasons].

write_read_case(Dir, {usable, Op, Args, Want, Line} = A) ->
    {Op, Opcode, Arity, _} = lists:keyfind(Op, 1, ops()),
    CaseDir = filename:join([Dir, "read", read_name(A)]),
    ok = filelib:ensure_path(CaseDir),
    Module = wb_encode:op_module(Arity, Opcode),
    ok = file:write_file(filename:join(CaseDir, "module.wasm"), Module),
    write_terms(filename:join(CaseDir, "case.config"),
                "A reading case from the spec tests. The module was written by the runner; "
                "the expected value is the upstream assertion's.",
                [{export, <<"f">>}, {params, lists:duplicate(Arity, i32)}, {results, [i32]},
                 {call, Args}, {expected, Want},
                 {module_sha256, sha256(Module)},
                 {upstream, [{repo, <<?REPO>>}, {commit, <<?COMMIT>>}, {file, <<?WAST>>}, {line, Line},
                             {instruction, <<"i32.", Op/binary>>}]}]).

write_write_case(Dir, Op, Assertions) ->
    {Op, _Opcode, Arity, Description} = lists:keyfind(Op, 1, ops()),
    CaseDir = filename:join([Dir, "write", Op]),
    ok = filelib:ensure_path(CaseDir),
    write_terms(filename:join(CaseDir, "case.config"),
                "A writing case from the spec tests. The calls and results are the upstream "
                "assertions for this instruction; the description is this project's.",
                [{export, <<"f">>}, {params, lists:duplicate(Arity, i32)}, {results, [i32]},
                 {description, unicode:characters_to_binary(Description)},
                 {calls, [{Args, Want} || {usable, _, Args, Want, _} <- Assertions]},
                 {upstream, [{repo, <<?REPO>>}, {commit, <<?COMMIT>>}, {file, <<?WAST>>},
                             {lines, [L || {usable, _, _, _, L} <- Assertions]},
                             {instruction, <<"i32.", Op/binary>>}]}]).

write_terms(Path, Comment, Terms) ->
    wb_terms:write(Path, Comment, Terms).

sha256(Bin) ->
    binary:encode_hex(crypto:hash(sha256, Bin), lowercase).
