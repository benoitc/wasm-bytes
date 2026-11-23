%% Provenance rules for saved replies, on fixtures written out here.
-module(wb_fixture_tests).

-include_lib("eunit/include/eunit.hrl").

fixture(Root, Kind, Task, Label, Config, Files) ->
    Dir = filename:join([Root, Kind, Task, Label]),
    ok = filelib:ensure_path(Dir),
    ok = file:write_file(filename:join(Dir, "fixture.config"),
                         [io_lib:format("~tp.~n", [T]) || T <- Config]),
    [ok = file:write_file(filename:join(Dir, Name), Body) || {Name, Body} <- Files],
    wb_fixture:load(Root, list_to_atom(Kind), Dir).

problems(F) ->
    [iolist_to_binary(P) || P <- wb_fixture:problems(F)].

kind_must_match_source_test() ->
    Root = wb_test_io:scratch("fixture-kinds"),
    Reply = [{"reply.txt", ~"00"}],
    E = fixture(Root, "examples", "write", "claims-trial",
                [{source, model_trial}, {expect, pass}], Reply),
    ?assertEqual([~"examples/ holds hand-written fixtures only (source must be hand_written)"],
                 problems(E)),
    T = fixture(Root, "trials", "write", "claims-hand",
                [{source, hand_written}, {expect, pass}], Reply),
    ?assertEqual([~"trials/ holds model trials only (source must be model_trial)"], problems(T)),
    ?assertNot(wb_fixture:is_trial(T)).

missing_parts_test() ->
    Root = wb_test_io:scratch("fixture-missing"),
    F = fixture(Root, "examples", "write", "bare", [{source, hand_written}], []),
    ?assertEqual([~"reply.txt is missing", ~"fixture.config has no expect",
                  ~"a hand-written fixture needs a note"], problems(F)),
    R = fixture(Root, "examples", "revise", "no-base",
                [{source, hand_written}, {expect, pass}, {note, "a note"}],
                [{"reply.txt", ~"00"}]),
    ?assertEqual([~"a revise fixture must name its base"], problems(R)).

trial_needs_its_record_test() ->
    Root = wb_test_io:scratch("fixture-trial"),
    F = fixture(Root, "trials", "digits", "half",
                [{source, model_trial}, {expect, pass}, {model, "m"}],
                [{"reply.txt", ~"00"}]),
    ?assertEqual([~"prompt.txt is missing", ~"interface is not recorded",
                  ~"recorded_on is not recorded"], problems(F)).

base_reply_test() ->
    Root = wb_test_io:scratch("fixture-base"),
    NoBase = fixture(Root, "trials", "revise", "x",
                     [{source, model_trial}, {expect, pass}], [{"reply.txt", ~"00"}]),
    ?assertEqual({error, no_base}, wb_fixture:base_reply(Root, NoBase)),
    Missing = fixture(Root, "trials", "revise", "y",
                      [{source, model_trial}, {expect, pass}, {base, "write/absent"}],
                      [{"reply.txt", ~"00"}]),
    ?assertMatch({error, {_, enoent}}, wb_fixture:base_reply(Root, Missing)).

unknown_task_test() ->
    Root = wb_test_io:scratch("fixture-task"),
    ?assertError({unknown_task, _},
                 fixture(Root, "examples", "rewrite", "x", [{source, hand_written}], [])).

empty_root_test() ->
    ?assertEqual([], wb_fixture:all(wb_test_io:scratch("fixture-empty"))).
