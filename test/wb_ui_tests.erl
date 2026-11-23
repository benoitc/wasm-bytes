%% The ui task: what counts as a page, the report, and, when Node and Chrome
%% are installed, the browser checks on the constructed examples.
-module(wb_ui_tests).

-include_lib("eunit/include/eunit.hrl").

text(P) ->
    {ok, Bin} = file:read_file(filename:join(wb_test_io:root(), P)),
    Bin.

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

not_html_test() ->
    {ok, R} = wb_ui:check(wb_test_io:root(), ~"```html\n<!doctype html><p>hi</p>\n```"),
    ?assertMatch(#{verdict := not_html, why := ~"```html"}, R),
    ?assert(has(iolist_to_binary(wb_ui:report(R)), ~"not an HTML document")),
    {ok, Prose} = wb_ui:check(wb_test_io:root(), ~"Here is the page:\n<!doctype html>"),
    ?assertMatch(#{verdict := not_html, why := ~"Here is the page:"}, Prose).

report_test() ->
    R = #{task => ui, verdict => ui_failed, text_bytes => 1000, browser => ~"Chrome/1",
          checks => [{loads, true, ~"modules instantiated: original, reversed"},
                     {uses_module, false, ~"original not shown"}]},
    Out = iolist_to_binary(wb_ui:report(R)),
    ?assert(has(Out, ~"check    ok   loads: modules instantiated")),
    ?assert(has(Out, ~"check    FAIL uses_module: original not shown")),
    ?assert(has(Out, ~"verdict  ui_failed")).

%% NODE and CHROME name the tools; a path that is not there is not found.
tools_test() ->
    Old = os:getenv("NODE"),
    try
        os:putenv("NODE", "/no/such/node"),
        case wb_ui:tools() of
            {ok, Node, _} -> ?assertEqual("/no/such/node", Node);
            {error, Missing} -> ?assert(lists:member(Missing, [node, chrome]))
        end
    after
        case Old of
            false -> os:unsetenv("NODE");
            _ -> os:putenv("NODE", Old)
        end
    end.

browser_test_() ->
    case wb_ui:tools() of
        {ok, _, _} ->
            {setup,
             fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
             fun(_) -> ok end,
             [{"the reference page passes every check", {timeout, 120, fun reference/0}},
              {"a page that computes the pan itself fails only uses_module", {timeout, 120, fun computes/0}},
              {"a toggle that switches straight off fails sound_on", {timeout, 120, fun toggle/0}}]};
        {error, _} ->
            [{"Node or Chrome is not installed: the browser checks are skipped", fun() -> ok end}]
    end.

checks(P) ->
    {ok, R} = wb_ui:check(wb_test_io:root(), text(P)),
    R.

reference() ->
    R = checks("examples/ui/reference/reply.txt"),
    ?assertMatch(#{verdict := pass}, R),
    ?assertEqual(13, length(maps:get(checks, R))).      % html is checked before the browser

computes() ->
    #{verdict := ui_failed, checks := Checks} = checks("examples/ui/computes-pan/reply.txt"),
    ?assertEqual([uses_module], [N || {N, false, _} <- Checks]).

toggle() ->
    #{verdict := ui_failed, checks := Checks} = checks("examples/ui/toggle-off/reply.txt"),
    ?assertMatch({sound_on, false, _}, lists:keyfind(sound_on, 1, Checks)).
