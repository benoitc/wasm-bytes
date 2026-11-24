%% The CodeContests track: writing cases from competitive programming problems.
%%
%% The source is the deepmind/code_contests dataset on Hugging Face, at a
%% pinned revision. `scripts/codecontests-export.py' reads its parquet files
%% and keeps the problems whose every test reads one or two integers and
%% prints one integer. Such a problem becomes `f(i32) -> i32' or
%% `f(i32, i32) -> i32': a test whose input is "5 3" and whose output is "2"
%% becomes the call `f(5, 3)', expected to return 2.
%%
%% The model sees the problem statement, which contains the public tests as
%% examples. It is graded on the private and generated tests only, none of
%% which the prompt shows.
-module(wb_contests).

-export([prepare/2, call_of/1, revision/0]).

-define(REVISION, "802411c3010cb00d1b05bad57ca77365a3c699d6").
-define(DATASET, "https://huggingface.co/datasets/deepmind/code_contests").
-define(MIN_I32, -2147483648).
-define(MAX_I32, 2147483647).
%% A contest program runs for up to a few seconds; this budget gives a
%% candidate room for loops over the inputs the tests use.
-define(FUEL, 200_000_000).
-define(DEADLINE_MS, 5_000).

-spec revision() -> binary().
revision() -> <<?REVISION>>.

%% `From' is the export's JSON lines. `sample' is `all' or how many problems
%% to keep, in the seeded order.
-spec prepare(file:filename(), map()) -> {ok, map()}.
prepare(From, #{out := Out, seed := Seed, sample := Sample}) ->
    {ok, Text} = file:read_file(From),
    Lines = [json:decode(L) || L <- binary:split(Text, <<"\n">>, [global]), L =/= <<>>],
    [Summary] = [S || #{<<"_summary">> := S} <- Lines],
    Problems = [P || P <- Lines, not is_map_key(<<"_summary">>, P)],
    Results = [problem(P) || P <- Problems],
    Usable = [U || {usable, _} = U <- Results],
    Ids = [Id || {usable, #{id := Id}} <- Usable],
    ById = maps:from_list([{Id, U} || {usable, #{id := Id} = U} <- Usable]),
    Order = wb_spec:order(Seed, Ids),
    Chosen = case Sample of
                 all -> Order;
                 N -> lists:sublist(Order, N)
             end,
    Dir = filename:join(Out, "codecontests"),
    _ = file:del_dir_r(Dir),
    [write_case(Dir, maps:get(Id, ById)) || Id <- Chosen],
    ExportSkipped = [{K, V} || K := V <- maps:get(<<"skipped">>, Summary)],
    Skipped = lists:keysort(1, ExportSkipped ++ count([R || {skipped, R} <- Results])),
    Selection = [{source, <<?DATASET>>}, {revision, <<?REVISION>>},
                 {files, maps:get(<<"files">>, Summary)},
                 {seed, Seed},
                 {examined, maps:get(<<"examined">>, Summary)},
                 {usable, length(Usable)},
                 {skipped, Skipped},
                 {write, Chosen}],
    ok = wb_terms:write(filename:join(Dir, "selection.config"),
                        "Written by bin/wasm-bytes prepare codecontests. Every problem in the "
                        "files is examined once; a usable one maps to integer calls.", Selection),
    {ok, maps:from_list(Selection)}.

count(Reasons) ->
    [{R, length([x || R1 <- Reasons, R1 =:= R])} || R <- lists:usort(Reasons)].

problem(P) ->
    #{<<"split">> := Split, <<"row">> := Row, <<"name">> := Name} = P,
    Id = iolist_to_binary([Split, "-", integer_to_list(Row), "-", slug(Name)]),
    Graded = tests(P, <<"private_tests">>) ++ tests(P, <<"generated_tests">>),
    Calls = [{call_of(In), call_of(Out)} || {In, Out} <- Graded],
    Values = lists:append([Args ++ Want || {Args, Want} <- Calls]),
    Distinct = lists:usort(Calls),
    if
        Graded =:= [] ->
            {skipped, <<"it has no private or generated tests to grade with">>};
        not is_binary(map_get(<<"description">>, P)) orelse map_get(<<"description">>, P) =:= <<>> ->
            {skipped, <<"it has no statement">>};
        true ->
            case lists:all(fun(V) -> V >= ?MIN_I32 andalso V =< ?MAX_I32 end, Values) of
                false ->
                    {skipped, <<"a test value does not fit in 32 bits">>};
                true ->
                    case length(lists:usort([A || {A, _} <- Distinct])) =:= length(Distinct) of
                        false -> {skipped, <<"two tests give different answers for the same input">>};
                        true -> {usable, #{id => Id, problem => P,
                                           calls => [{Args, W} || {Args, [W]} <- Distinct]}}
                    end
            end
    end.

tests(P, Key) ->
    #{<<"input">> := Ins, <<"output">> := Outs} = maps:get(Key, P),
    lists:zip(Ins, Outs).

%% The integers a test's input or output holds, in order.
-spec call_of(binary()) -> [integer()].
call_of(Text) ->
    [binary_to_integer(T) || T <- string:lexemes(Text, " \t\r\n")].

slug(Name) ->
    Lower = string:lowercase(Name),
    Dashed = re:replace(Lower, "[^a-z0-9]+", "-", [global, {return, binary}]),
    string:slice(string:trim(Dashed, both, "-"), 0, 40).

write_case(Dir, #{id := Id, problem := P, calls := Calls}) ->
    CaseDir = filename:join([Dir, "write", Id]),
    ok = filelib:ensure_path(CaseDir),
    ok = file:write_file(filename:join(CaseDir, "statement.txt"), map_get(<<"description">>, P)),
    Arity = map_get(<<"arity">>, P),
    #{<<"input">> := [ExIn | _], <<"output">> := [ExOut | _]} =
        case map_get(<<"public_tests">>, P) of
            #{<<"input">> := [_ | _]} = Public -> Public;
            _ -> map_get(<<"private_tests">>, P)
        end,
    ok = wb_terms:write(
           filename:join(CaseDir, "case.config"),
           "A writing case from CodeContests. The statement is the dataset's; every call below "
           "is a private or generated test, so none is shown in the prompt. A test's input "
           "integers are the call's arguments, in order, and its output is the expected return.",
           [{export, <<"f">>}, {params, lists:duplicate(Arity, i32)}, {results, [i32]},
            {statement, <<"statement.txt">>},
            {mapping, [{input, ExIn}, {output, ExOut},
                       {call, call_of(ExIn)}, {expected, hd(call_of(ExOut))}]},
            {limits, [{fuel, ?FUEL}, {deadline_ms, ?DEADLINE_MS}]},
            {calls, Calls},
            {upstream, [{dataset, <<?DATASET>>}, {revision, <<?REVISION>>},
                        {split, map_get(<<"split">>, P)}, {row, map_get(<<"row">>, P)},
                        {name, map_get(<<"name">>, P)}, {source, source(map_get(<<"source">>, P))},
                        {difficulty, map_get(<<"difficulty">>, P)},
                        {cf_contest_id, map_get(<<"cf_contest_id">>, P)},
                        {cf_index, map_get(<<"cf_index">>, P)},
                        {license, <<"CC BY 4.0, as the dataset is published">>}]}]).

%% The `source' enum of the dataset's `ContestProblem'.
source(0) -> <<"unknown">>;
source(1) -> <<"CodeChef">>;
source(2) -> <<"Codeforces">>;
source(3) -> <<"HackerEarth">>;
source(4) -> <<"CodeJam">>;
source(5) -> <<"AtCoder">>;
source(6) -> <<"Aizu">>;
source(N) -> integer_to_binary(N).
