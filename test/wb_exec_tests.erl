-module(wb_exec_tests).

-include_lib("eunit/include/eunit.hrl").

exec_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"fuel stops a loop, and the next input still runs", fun fuel/0},
      {"a deadline kills the worker; after three, the rest is not run",
       {timeout, 30, fun deadline/0}},
      {"a trap is reported for its input", fun trap/0}]}.

spin_unless_zero() ->
    {ok, M} = wasm:compile({wat, ~"""
        (module
          (func (export "retry") (param i32) (result i32)
            (block
              (br_if 0 (i32.eqz (local.get 0)))
              (loop (br 0)))
            (i32.const 7)))
        """}),
    M.

fuel() ->
    {ok, Results} = wb_exec:run(spin_unless_zero(), ~"retry", [1, 0, 2]),
    ?assertMatch([{1, {error, #{class := exhaustion, kind := out_of_fuel}}},
                  {0, {ok, 7}},
                  {2, {error, #{class := exhaustion, kind := out_of_fuel}}}],
                 Results).

deadline() ->
    Opts = #{fuel => infinity, deadline_ms => 100},
    {ok, Results} = wb_exec:run(spin_unless_zero(), ~"retry", [0, 1, 0, 2, 3, 0], Opts),
    ?assertMatch([{0, {ok, 7}},
                  {1, {error, #{kind := timeout}}},
                  {0, {ok, 7}},
                  {2, {error, #{kind := timeout}}},
                  {3, {error, #{kind := timeout}}},
                  {0, not_run}],
                 Results),
    %% The killed workers were linked to a process of wb_exec's, not to us.
    receive {'EXIT', _, _} = Exit -> ?assertEqual(no_exit, Exit) after 0 -> ok end.

trap() ->
    {ok, M} = wasm:compile({wat, ~"""
        (module
          (func (export "retry") (param i32) (result i32)
            (i32.div_s (i32.const 1) (local.get 0))))
        """}),
    {ok, Results} = wb_exec:run(M, ~"retry", [1, 0]),
    ?assertMatch([{1, {ok, 1}}, {0, {error, #{class := trap, kind := integer_divide_by_zero}}}],
                 Results).
