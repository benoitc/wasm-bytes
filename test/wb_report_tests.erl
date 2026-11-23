%% Report lines for outcomes the saved replies do not produce, from reports
%% written out here.
-module(wb_report_tests).

-include_lib("eunit/include/eunit.hrl").

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

not_run_test() ->
    R = #{task => write, verdict => execution_failure, text_bytes => 0, bytes => <<0>>,
          results => [{1, {error, #{class => exhaustion, kind => timeout}}}, {2, not_run}],
          failures => [{1, #{class => exhaustion, kind => timeout}}, {2, not_run}],
          wrong => []},
    Text = iolist_to_binary(wb_report:report(R)),
    ?assert(has(Text, ~"2 calls did not return a result")),
    ?assert(has(Text, ~"input 1: exhaustion/timeout")),
    ?assert(has(Text, ~"input 2: not run, after too many deadlines")).

runner_error_test() ->
    R = #{task => write, verdict => runner_error, text_bytes => 2, why => {error, boom, []}},
    Text = iolist_to_binary(wb_report:report(R)),
    ?assert(has(Text, ~"runner   {error,boom,[]}")),
    ?assert(has(Text, ~"verdict  runner_error")).

%% A revision that is not hex has no diff and no changes to show.
revision_without_bytes_test() ->
    Base = #{task => write, verdict => pass, text_bytes => 3, bytes => <<0, 1, 2>>},
    Revised = #{task => revise, verdict => malformed_hex, text_bytes => 5, why => empty},
    Text = iolist_to_binary(wb_report:revision(~"base.txt",
                                               #{base => Base, revised => Revised, intended => []})),
    ?assert(has(Text, ~"base     base.txt: 3 bytes, passes task 1")),
    ?assert(has(Text, ~"diff     none: the revision is not hex")),
    ?assert(has(Text, ~"changes  not measured: the revision did not run")).

outcome_test() ->
    ?assertEqual(~"1", iolist_to_binary(wb_report:outcome({ok, 1}))),
    ?assertEqual(~"error trap/unreachable",
                 iolist_to_binary(wb_report:outcome({error, #{class => trap, kind => unreachable}}))),
    ?assertEqual(~"error", iolist_to_binary(wb_report:outcome({error, other}))),
    ?assertEqual(~"not run", iolist_to_binary(wb_report:outcome(not_run))).
