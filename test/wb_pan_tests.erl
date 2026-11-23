%% The DX-Ball pan tasks: the reference taken from REA's recorded
%% instructions, the reversal, how many changes are reported, and the demo
%% page built from two recorded replies.
-module(wb_pan_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PAN, "trials/pan/claude-sonnet-5-5-1/reply.txt").
-define(REVERSED, "trials/reverse/claude-sonnet-5-5-1/reply.txt").

path(P) -> filename:join(wb_test_io:root(), P).

text(P) ->
    {ok, Bin} = file:read_file(path(P)),
    Bin.

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

%% x * 1.5625 - 500, truncated toward zero: -498.4375 is -498, not -499.
reference_test() ->
    Cases = [{0, -500}, {1, -498}, {16, -475}, {319, -1}, {320, 0}, {321, 1},
             {498, 278}, {639, 498}, {640, 500}],
    [?assertEqual({X, Want}, {X, wb_task:expected(pan, X)}) || {X, Want} <- Cases].

reverse_mirrors_test() ->
    [?assertEqual({X, wb_task:expected(pan, 640 - X)}, {X, wb_task:expected(reverse, X)})
     || X <- wb_task:inputs(reverse)],
    ?assertEqual(0, wb_task:expected(reverse, 320)).

inputs_test() ->
    ?assertEqual(lists:seq(0, 640), wb_task:inputs(pan)),
    ?assertEqual(lists:seq(0, 640), wb_task:inputs(reverse)).

%% Every position but the centre changes sign.
intended_changes_test() ->
    Changes = wb_task:intended_changes(reverse),
    ?assertEqual(640, length(Changes)),
    ?assertNot(lists:keymember(320, 1, Changes)),
    ?assertEqual({0, -500, 500}, lists:keyfind(0, 1, Changes)),
    ?assertEqual({640, 500, -500}, lists:keyfind(640, 1, Changes)),
    ?assertEqual({ok, pan}, wb_task:base(reverse)),
    ?assertEqual(none, wb_task:base(pan)).

pan_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"a numeric off-by-one is grouped by its difference", fun off_by_one/0},
      {"a reversal reports its 640 changes in a few lines", fun reversal_report/0},
      {"the CLI checks and prompts the pan tasks", fun cli/0},
      {"the demo page carries the recorded bytes", fun demo_page/0},
      {"the demo refuses replies that do not pass", fun demo_refuses/0}]}.

off_by_one() ->
    R = wb_check:check(pan, text("examples/pan/integer-division/reply.txt")),
    ?assertMatch(#{verdict := wrong_answer}, R),
    Out = iolist_to_binary(wb_report:report(R)),
    ?assert(has(Out, ~"first    input 1: expected -498, got -499")),
    ?assert(has(Out, ~"1 less than expected on 300 inputs:")),
    ?assert(has(Out, ~"1 to 15, 17 to 31")).

reversal_report() ->
    {ok, Rev} = wb_check:check_revision(reverse, text(?PAN), text(?REVERSED)),
    ?assertMatch(#{revised := #{verdict := pass}}, Rev),
    Out = iolist_to_binary(wb_report:revision(~"pan", Rev)),
    ?assert(has(Out, ~"passes the pan task")),
    ?assert(has(Out, ~"640 of 641 inputs changed result")),
    ?assert(has(Out, ~"0: -500 -> 500  (requested)")),
    ?assert(has(Out, ~"0 to 319, 321 to 640")),
    ?assert(has(Out, ~"request  done: all 640 requested changes; no other result changed")),
    %% A summary, not 640 lines.
    ?assert(length(binary:split(Out, ~"\n", [global])) < 30).

cli() ->
    Run = fun(Args) ->
              Err = wb_test_io:device(),
              {Code, Out} = wb_test_io:capture(fun() -> wasm_bytes:run(Args, Err) end),
              {Code, Out, wb_test_io:text(Err)}
          end,
    {0, Pan, _} = Run(["check", "pan", ?PAN]),
    ?assert(has(Pan, ~"641 of 641 match the reference")),
    {0, Rev, _} = Run(["check", "reverse", ?REVERSED, "--base", ?PAN]),
    ?assert(has(Rev, ~"verdict  pass")),
    {0, Prompt, _} = Run(["prompt", "pan"]),
    ?assertEqual(text("prompts/pan.txt"), Prompt),
    {2, _, NoGuide} = Run(["prompt", "pan", "--guided"]),
    ?assert(has(NoGuide, ~"the pan task has no guided prompt")),
    {0, RevPrompt, _} = Run(["prompt", "reverse", "--base", ?PAN]),
    ?assertEqual(text("trials/reverse/claude-sonnet-5-5-1/prompt.txt"), RevPrompt),
    {1, _, Refused} = Run(["prompt", "reverse", "--base", "examples/pan/integer-division/reply.txt"]),
    ?assert(has(Refused, ~"does not pass the pan task")).

demo_page() ->
    Out = wb_test_io:scratch("pan-demo"),
    {ok, Index} = wb_pan_demo:build(wb_test_io:root(), path(?PAN), path(?REVERSED), Out),
    ?assertEqual(filename:join(Out, "index.html"), Index),
    [?assert(filelib:is_file(filename:join(Out, F))) || F <- ["index.html", "app.js", "modules.js"]],
    {ok, Js} = file:read_file(filename:join(Out, "modules.js")),
    [<<"window.PAN_MODULES = ", Json0/binary>>] =
        [L || L <- binary:split(Js, ~"\n", [global]), has(L, ~"PAN_MODULES")],
    Json = binary:part(Json0, 0, byte_size(Json0) - 1),          % the trailing ;
    #{<<"original">> := O, <<"reversed">> := R} = json:decode(Json),
    [begin
         Bytes = base64:decode(maps:get(<<"bytes">>, M)),
         Dir = filename:dirname(path(binary_to_list(maps:get(<<"reply">>, M)))),
         ?assertEqual(wb_trace:recorded_sha256(Dir), maps:get(<<"sha256">>, M)),
         ?assertEqual(wb_trace:sha256(Bytes), maps:get(<<"sha256">>, M)),
         ?assertEqual(~"claude-sonnet-5-5", maps:get(<<"model">>, M))
     end || M <- [O, R]].

demo_refuses() ->
    Out = wb_test_io:scratch("pan-demo-refused"),
    ?assertMatch({error, {original_refused, #{verdict := wrong_answer}}},
                 wb_pan_demo:build(wb_test_io:root(), path("examples/pan/integer-division/reply.txt"),
                                   path(?REVERSED), Out)),
    %% The original pan module offered as its own reversal changes nothing.
    ?assertMatch({error, {reversed_refused, #{verdict := wrong_answer}}},
                 wb_pan_demo:build(wb_test_io:root(), path(?PAN), path(?PAN), Out)).
