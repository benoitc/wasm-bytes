%% The saved replies: each gets the verdict it is labelled with, each says
%% where it came from, and the details the README promises are there.
-module(wb_fixtures_tests).

-include_lib("eunit/include/eunit.hrl").

fixtures_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"every fixture gets the verdict it is labelled with", {timeout, 60, fun labelled/0}},
      {"examples are hand-written and none counts as a trial", fun provenance/0},
      {"a trial without its prompt is not counted", fun incomplete_trial/0},
      {"write/accepted passes on every input", fun accepted/0},
      {"write/misses-599 is wrong on 599 alone", fun misses_599/0},
      {"write/loops-on-negative fails on the negative inputs alone", fun loops/0},
      {"write/truncated is refused, not completed", fun truncated/0},
      {"write/prose-around-hex stops at the first character", fun prose/0},
      {"revise/accepted changes exactly 408 and 501", fun revise_accepted/0},
      {"revise/replaces-429 shows the change nobody asked for", fun replaces_429/0},
      {"revise/stale-lengths keeps the lengths it was sent", fun stale_lengths/0},
      {"each module.wat behaves like the bytes beside it", {timeout, 60, fun wat_matches_hex/0}},
      {"the rendered revise prompt matches the template", fun rendered_prompt/0},
      {"each trial's prompt is the one the runner gives", fun trial_prompts/0},
      {"grouped output names every wrong input", fun grouped_output/0},
      {"the guided prompts share one reference card and give no answer away", fun guided_prompts/0},
      {"the demo answers 0", {timeout, 60, fun demo/0}}]}.

root() ->
    {ok, Cwd} = file:get_cwd(),
    Cwd.

fixture(Kind, Task, Label) ->
    wb_fixture:load(root(), Kind, filename:join([root(), Kind, Task, Label])).

check(Task, Label) ->
    #{reply := Reply} = fixture(examples, Task, Label),
    wb_check:check(Task, Reply).

revision(Label) ->
    F = fixture(examples, revise, Label),
    {ok, _, Base} = wb_fixture:base_reply(root(), F),
    {ok, Rev} = wb_check:check_revision(Base, maps:get(reply, F)),
    Rev.

labelled() ->
    [begin
         Got = case Task of
                   _ when Task =/= revise ->
                       maps:get(verdict, wb_check:check(Task, Reply));
                   revise ->
                       {ok, _, Base} = wb_fixture:base_reply(root(), F),
                       {ok, #{revised := R}} = wb_check:check_revision(Base, Reply),
                       maps:get(verdict, R)
               end,
         ?assertEqual({Label, Expect}, {Label, Got})
     end || #{task := Task, label := Label, reply := Reply, config := #{expect := Expect}} = F
                <- wb_fixture:all(root())].

provenance() ->
    All = wb_fixture:all(root()),
    ?assert(length(All) >= 12),
    [begin
         ?assertEqual({Label, []}, {Label, wb_fixture:problems(F)}),
         ?assertEqual(hand_written, maps:get(source, C)),
         ?assertNot(wb_fixture:is_trial(F))
     end || #{kind := examples, label := Label, config := C} = F <- All],
    %% Every trial under trials/ is complete, so it is counted.
    [begin
         ?assertEqual({Label, []}, {Label, wb_fixture:problems(F)}),
         ?assert(wb_fixture:is_trial(F))
     end || #{kind := trials, label := Label} = F <- All].

incomplete_trial() ->
    Dir = filename:join([scratch(), "trials", "write", "no-prompt"]),
    ok = file:del_dir_r(scratch()),
    ok = filelib:ensure_dir(filename:join(Dir, "x")),
    ok = file:write_file(filename:join(Dir, "reply.txt"), ~"00"),
    ok = file:write_file(filename:join(Dir, "fixture.config"),
                         <<"{source, model_trial}.\n{model, \"some-model\"}.\n"
                           "{interface, \"a chat window\"}.\n{recorded_on, \"2026-11-23\"}.\n"
                           "{expect, malformed_wasm}.\n">>),
    F = wb_fixture:load(scratch(), trials, Dir),
    ?assertEqual([~"prompt.txt is missing"], [iolist_to_binary(P) || P <- wb_fixture:problems(F)]),
    ?assertNot(wb_fixture:is_trial(F)),
    ok = file:write_file(filename:join(Dir, "prompt.txt"), ~"the prompt"),
    ?assert(wb_fixture:is_trial(wb_fixture:load(scratch(), trials, Dir))).

scratch() ->
    Dir = filename:join([root(), "_build", "test", "scratch"]),
    ok = filelib:ensure_dir(filename:join(Dir, "x")),
    Dir.

accepted() ->
    R = check(write, ~"accepted"),
    ?assertMatch(#{verdict := pass, failures := [], wrong := []}, R),
    ?assertEqual(54, byte_size(maps:get(bytes, R))),
    ?assertEqual(length(wb_task:inputs(write)), length(maps:get(results, R))).

misses_599() ->
    ?assertMatch(#{verdict := wrong_answer, failures := [], wrong := [{599, 1, 0}]},
                 check(write, ~"misses-599")).

loops() ->
    #{verdict := execution_failure, failures := Failures, wrong := []} =
        check(write, ~"loops-on-negative"),
    ?assertEqual([X || X <- wb_task:inputs(write), X < 0], [X || {X, _} <- Failures]),
    ?assert(lists:all(fun({_, #{kind := K}}) -> K =:= out_of_fuel end, Failures)).

truncated() ->
    R = check(write, ~"truncated"),
    ?assertMatch(#{verdict := malformed_wasm, why := #{kind := unexpected_end}}, R),
    #{bytes := Accepted} = check(write, ~"accepted"),
    ?assertEqual(binary:part(Accepted, 0, 53), maps:get(bytes, R)).

prose() ->
    ?assertMatch(#{verdict := malformed_hex, why := {not_hex, 1, 1, $H}},
                 check(write, ~"prose-around-hex")).

revise_accepted() ->
    #{revised := #{verdict := pass}, changes := Changes} = revision(~"accepted"),
    ?assertEqual([{408, {ok, 0}, {ok, 1}}, {501, {ok, 1}, {ok, 0}}], Changes).

replaces_429() ->
    #{revised := #{verdict := wrong_answer, wrong := Wrong}, changes := Changes} =
        revision(~"replaces-429"),
    ?assertEqual([{429, 1, 0}], Wrong),
    ?assertEqual([{408, {ok, 0}, {ok, 1}}, {429, {ok, 1}, {ok, 0}}, {501, {ok, 1}, {ok, 0}}],
                 Changes).

stale_lengths() ->
    #{revised := #{verdict := malformed_wasm, bytes := Stale}, hunks := Hunks} =
        revision(~"stale-lengths"),
    #{revised := #{bytes := Good}} = revision(~"accepted"),
    %% Same bytes as the good revision, except the two lengths, which still
    %% hold their task 1 values: nothing recomputed them.
    ?assertEqual(byte_size(Good), byte_size(Stale)),
    ?assertEqual({16#15, 16#13}, {binary:at(Stale, 16#20), binary:at(Stale, 16#22)}),
    ?assertEqual({16#23, 16#21}, {binary:at(Good, 16#20), binary:at(Good, 16#22)}),
    ?assertEqual([16#24, 16#2a, 16#34], [At || #{base_at := At} <- Hunks]).

wat_matches_hex() ->
    Dirs = filelib:wildcard(filename:join([root(), "examples", "*", "*", "module.wat"])),
    ?assert(length(Dirs) >= 8),
    [begin
         Dir = filename:dirname(Wat),
         {ok, Src} = file:read_file(Wat),
         {ok, Text} = file:read_file(filename:join(Dir, "reply.txt")),
         {ok, Bytes} = wb_hex:decode(Text),
         {ok, FromWat} = wasm:compile({wat, Src}),
         {ok, FromHex} = wasm:compile(Bytes),
         Task = task_of(Dir),
         ?assertEqual({Dir, outcomes(Task, FromWat)}, {Dir, outcomes(Task, FromHex)})
     end || Wat <- Dirs].

task_of(Dir) ->
    Name = filename:basename(filename:dirname(Dir)),
    hd([T || T <- wb_task:names(), atom_to_list(T) =:= Name]).

outcomes(Task, Module) ->
    #{export := Export} = wb_task:get(Task),
    {ok, Results} = wb_exec:run(Module, Export, wb_task:inputs(Task)),
    [case O of
         {ok, V} -> {X, V};
         {error, #{class := C, kind := K}} -> {X, C, K}
     end || {X, O} <- Results].

rendered_prompt() ->
    #{reply := Base} = fixture(examples, write, ~"accepted"),
    {ok, Rendered} = wasm_bytes:render_revise_prompt(root(), Base),
    {ok, Saved} = file:read_file(filename:join([root(), "prompts", "revise.example.txt"])),
    ?assertEqual(Saved, iolist_to_binary(Rendered)),
    ?assertEqual(nomatch, binary:match(Saved, ~"{{")).

trial_prompts() ->
    Trials = [F || #{kind := trials} = F <- wb_fixture:all(root())],
    ?assert(length([T || #{task := digits} = T <- Trials]) >= 3),
    [case F of
         #{task := revise, prompt := Prompt} ->
             {ok, _, Base} = wb_fixture:base_reply(root(), F),
             {ok, Rendered} = wasm_bytes:render_revise_prompt(root(), Base),
             ?assertEqual({Label, iolist_to_binary(Rendered)}, {Label, Prompt});
         #{task := Task, prompt := Prompt, config := C} ->
             %% A one-prompt task: the prompt file for its variant, as it is.
             {ok, File} = wb_task:prompt(Task, maps:get(prompt_variant, C, baseline)),
             {ok, Want} = file:read_file(filename:join(root(), File)),
             ?assertEqual({Task, Label, Want}, {Task, Label, Prompt})
     end || #{label := Label} = F <- Trials].

guided_prompts() ->
    Cards = [begin
                 {ok, P} = wb_task:prompt(T, guided),
                 {ok, Bin} = file:read_file(filename:join(root(), P)),
                 {ok, Base} = file:read_file(filename:join(root(), element(2, wb_task:prompt(T, baseline)))),
                 %% The guided prompt is the baseline with the card inserted.
                 [Head, _] = binary:split(Base, ~"Reply with only the bytes"),
                 ?assertEqual(Head, binary:part(Bin, 0, byte_size(Head))),
                 [Card, _] = binary:split(binary:part(Bin, byte_size(Head), byte_size(Bin) - byte_size(Head)),
                                          ~"Reply with only the bytes"),
                 Card
             end || T <- [write, digits]],
    [Card, Card] = Cards,
    %% No constant the tasks need appears encoded in the card.
    [?assertEqual({Bytes, nomatch}, {Bytes, binary:match(Card, Bytes)})
     || Bytes <- [~"ad 03", ~"f4 03", ~"e4 00", ~"98 03", ~"f5 03", ~"41 0a"]].

grouped_output() ->
    Wrong = [{X, wb_task:expected(write, X), 1 - wb_task:expected(write, X)}
             || X <- wb_task:inputs(write), X =/= 429, X =/= 599],
    Text = iolist_to_binary(wb_report:report(#{task => write, verdict => wrong_answer,
                                                text_bytes => 0, bytes => <<>>,
                                                results => [], failures => [],
                                                wrong => Wrong})),
    ?assertNotEqual(nomatch, binary:match(Text, ~"expected 1, got 0 on 99 inputs:")),
    ?assertNotEqual(nomatch, binary:match(Text, ~"500 to 598")),
    ?assertNotEqual(nomatch, binary:match(Text, ~"99 to 428, 430 to 499")),
    ?assertNotEqual(nomatch, binary:match(Text, ~"-1 to 1,")).

demo() ->
    ?assertEqual(0, quietly(fun() -> wasm_bytes:demo(root()) end)).

%% Runs `F' with its output collected instead of printed.
quietly(F) ->
    Old = group_leader(),
    Sink = spawn_link(fun sink/0),
    group_leader(Sink, self()),
    try F()
    after group_leader(Old, self())
    end.

sink() ->
    receive
        {io_request, From, Ref, _Req} ->
            From ! {io_reply, Ref, ok},
            sink()
    end.
