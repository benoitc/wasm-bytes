%% The reading and writing tracks: cases, their preparation from pinned
%% sources, the saved replies, and the batch totals the documentation quotes.
-module(wb_case_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LABEL, "claude-sonnet-5-5-1").

case_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"a call can take two arguments", fun two_arguments/0},
      {"the runner's add module is the 39 bytes the reading guide shows", fun add_module/0},
      {"a reading reply is one signed integer and nothing else", fun read_answer/0},
      {"the spec source gives 374 assertions, 364 usable", fun spec_counts/0},
      {"the spec sample is what prepare writes for its seed", fun spec_reproduces/0},
      {"every saved reply to a case gets its recorded verdict", {timeout, 300, fun replies/0}},
      {"a model trial's prompt is the case's prompt, as sent", fun trial_prompts/0},
      {"each WasmBench case's binary returns its expected value", fun wasmbench_answers/0},
      {"each WasmBench case in the sample has an open license", fun wasmbench_licenses/0},
      {"each contest case maps its example test to a call", fun contest_mapping/0},
      {"the spec batch totals", fun spec_batch/0},
      {"the full run's summary matches its saved verdicts", fun corpus_summary/0},
      {"the command line: cases, prompt case, check case, batch", fun cli/0}]}.

root() ->
    wb_test_io:root().

cases() ->
    filename:join(root(), "cases").

two_arguments() ->
    {ok, M} = wasm:compile(wb_encode:op_module(2, 16#6a)),
    ?assertEqual({ok, [{[2147483647, 1], {ok, -2147483648}}, {[1, 1], {ok, 2}}]},
                 wb_exec:run(M, <<"f">>, [[2147483647, 1], [1, 1]])).

add_module() ->
    Bytes = wb_encode:op_module(2, 16#6a),
    ?assertEqual(39, byte_size(Bytes)),
    ?assertEqual(<<"00 61 73 6d 01 00 00 00 01 07 01 60 02 7f 7f 01\n"
                   "7f 03 02 01 00 07 05 01 01 66 00 00 0a 09 01 07\n"
                   "00 20 00 20 01 6a 0b\n">>,
                 iolist_to_binary(wb_hex:encode(Bytes))),
    {ok, #{module := Module}} = wb_case:find(cases(), "spec/read/add-41"),
    ?assertEqual(Bytes, Module).

read_answer() ->
    ?assertEqual({ok, -2147483648}, wb_case:read_answer(<<"-2147483648">>)),
    ?assertEqual({ok, 42}, wb_case:read_answer(<<"  42\n">>)),
    ?assertEqual({ok, 3}, wb_case:read_answer(<<"+3">>)),
    [?assertMatch({error, {not_a_number, _}}, wb_case:read_answer(T))
     || T <- [<<"3.">>, <<"The answer is 3">>, <<>>, <<"0x10">>, <<"1 2">>, <<"```\n3\n```">>]],
    ?assertEqual({error, too_large}, wb_case:read_answer(binary:copy(<<"1">>, 2000))).

spec_counts() ->
    Out = wb_test_io:scratch("spec-all"),
    {ok, Sel} = wb_spec:prepare(root(), #{out => Out, seed => 2026, read => all, write => all}),
    ?assertEqual(374, maps:get(examined, Sel)),
    ?assertEqual(364, maps:get(usable, Sel)),
    ?assertEqual([{<<"the call traps, so there is no value to predict">>, 10}], maps:get(skipped, Sel)),
    ?assertEqual(364, length(maps:get(read, Sel))),
    ?assertEqual(31, length(maps:get(write, Sel))).

%% The committed sample is exactly what the documented command writes.
spec_reproduces() ->
    Out = wb_test_io:scratch("spec-sample"),
    {ok, _} = wb_spec:prepare(root(), #{out => Out, seed => 2026, read => 12, write => 8}),
    Mine = files(filename:join(Out, "spec")),
    Kept = files(filename:join(cases(), "spec")),
    ?assertEqual([F || {F, _} <- Kept], [F || {F, _} <- Mine]),
    [?assertEqual({F, A}, {F, B}) || {{F, A}, {F, B}} <- lists:zip(Kept, Mine)].

files(Dir) ->
    [{F, element(2, file:read_file(filename:join(Dir, F)))}
     || F <- lists:sort(filelib:wildcard("**/*", Dir)), filelib:is_regular(filename:join(Dir, F))].

replies() ->
    Replies = wb_case:replies(root()),
    ?assertEqual([], [{Id, Label} || #{case_id := Id, label := Label, config := C} <- Replies,
                                     not is_map_key(expect, C)]),
    ?assert(length([R || #{kind := trials} = R <- Replies]) >= 33),
    ?assert(length([R || #{kind := examples} = R <- Replies]) >= 3),
    [begin
         {ok, C} = wb_case:find(cases(), Id),
         #{verdict := V} = wb_case:check(C, Reply),
         ?assertEqual({Id, Label, Expect}, {Id, Label, V})
     end || #{case_id := Id, label := Label, reply := Reply, config := #{expect := Expect}} <- Replies].

trial_prompts() ->
    [begin
         {ok, C} = wb_case:find(cases(), Id),
         ?assertEqual({Id, wb_case:prompt(root(), C)}, {Id, Prompt}),
         ?assert(is_map_key(model, Config) andalso is_map_key(recorded_on, Config))
     end || #{kind := trials, case_id := Id, prompt := Prompt, config := Config} <- wb_case:replies(root())],
    [?assert(is_map_key(note, Config))
     || #{kind := examples, config := Config} <- wb_case:replies(root())].

%% The binary in the repository still answers what the case expects, in a
%% fresh instance, twice; no dataset download is needed.
wasmbench_answers() ->
    Cases = wb_case:all(cases(), "wasmbench"),
    ?assertEqual(8, length(Cases)),
    [begin
         ?assertEqual({Id, maps:get(module_sha256, C)}, {Id, sha256(Module)}),
         {ok, M} = wasm:compile(Module),
         {ok, [{_, Got1}]} = wb_exec:run(M, Export, [Args]),
         {ok, [{_, Got2}]} = wb_exec:run(M, Export, [Args]),
         ?assertEqual({Id, {ok, Want}}, {Id, Got1}),
         ?assertEqual(Got1, Got2)
     end || #{id := Id, module := Module, export := Export, call := Args, expected := Want} = C <- Cases].

wasmbench_licenses() ->
    [begin
         {license, L} = lists:keyfind(license, 1, Up),
         [Spdx | _] = binary:split(L, <<" ">>),
         ?assert(wb_wasmbench:open_license(Spdx))
     end || #{upstream := Up} <- wb_case:all(cases(), "wasmbench")].

contest_mapping() ->
    Cases = wb_case:all(cases(), "codecontests"),
    ?assertEqual(5, length(Cases)),
    [begin
         {ok, Terms} = file:consult(filename:join(Dir, "case.config")),
         Mapping = proplists:get_value(mapping, Terms),
         Input = proplists:get_value(input, Mapping),
         ?assertEqual(wb_contests:call_of(Input), proplists:get_value(call, Mapping)),
         ?assertEqual(length(Ps), length(proplists:get_value(call, Mapping))),
         ?assertEqual([proplists:get_value(expected, Mapping)],
                      wb_contests:call_of(proplists:get_value(output, Mapping))),
         ?assertMatch(#{fuel := _, deadline_ms := _}, Limits),
         ?assert(length(Calls) > 0)
     end || #{dir := Dir, params := Ps, limits := Limits, calls := Calls} <- Cases].

spec_batch() ->
    B = wb_case:batch(root(), cases(), "spec", ?LABEL),
    ?assertMatch(#{cases := 12, attempted := 12, passed := 12, missing := 0}, maps:get(read, B)),
    ?assertMatch(#{cases := 8, attempted := 8, valid := 8, passed := 8, missing := 0}, maps:get(write, B)).

%% The questions of the full run are rebuilt from the pinned sources, so
%% here only the saved verdicts are counted, against the summary.
corpus_summary() ->
    {ok, Terms} = file:consult(filename:join(root(), "trials/corpus/summary.config")),
    Label = binary_to_list(proplists:get_value(label, Terms)),
    Counts = proplists:get_value(counts, Terms),
    Configs = filelib:wildcard("trials/corpus/*/*/*/" ++ Label ++ "/fixture.config", root()),
    ?assertEqual(599, length(Configs)),
    Seen = [begin
                {ok, C} = file:consult(filename:join(root(), F)),
                ["trials", "corpus", Track, Direction | _] = filename:split(F),
                ?assert(filelib:is_regular(filename:join([root(), filename:dirname(F), "reply.txt"]))),
                {iolist_to_binary([Track, "/", Direction]), proplists:get_value(expect, C)}
            end || F <- Configs],
    [begin
         Mine = [V || {T, V} <- Seen, T =:= Key],
         ?assertEqual({Key, proplists:get_value(questions, Want)}, {Key, length(Mine)}),
         [?assertEqual({Key, V, N}, {Key, V, length([x || V1 <- Mine, V1 =:= V])})
          || {V, N} <- Want, V =/= questions]
     end || {Key, Want} <- Counts].

cli() ->
    {0, List, _} = run(["cases", "spec"]),
    ?assert(has(List, <<"spec/read/add-41">>) andalso has(List, <<"20 cases">>)),
    {0, Prompt, _} = run(["prompt", "case", "spec/read/add-41"]),
    ?assert(has(Prompt, <<"What signed integer does f(2147483647, 1) return?">>)),
    ?assertNot(has(Prompt, <<"add">>)),
    {0, Pass, _} = run(["check", "case", "spec/read/add-41",
                        filename:join(root(), "trials/cases/spec/read/add-41/" ?LABEL "/reply.txt")]),
    ?assert(has(Pass, <<"verdict  pass">>)),
    {1, Wrong, _} = run(["check", "case", "spec/write/add",
                         filename:join(root(), "examples/cases/spec/write/add/subtracts/reply.txt")]),
    ?assert(has(Wrong, <<"first    input (1, 1): expected 2, got 0">>)),
    {0, Batch, _} = run(["batch", "spec", ?LABEL]),
    ?assert(has(Batch, <<"12 correct predictions out of 12 attempted calls">>)),
    {2, _, Err} = run(["prompt", "case", "spec/read/no-such-case"]),
    ?assert(has(Err, <<"no case spec/read/no-such-case">>)).

run(Args) ->
    Err = wb_test_io:device(),
    {Code, Out} = wb_test_io:capture(fun() -> wasm_bytes:run(Args, Err) end),
    {Code, Out, wb_test_io:text(Err)}.

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

sha256(Bin) ->
    binary:encode_hex(crypto:hash(sha256, Bin), lowercase).
