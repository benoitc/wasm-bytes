%% Calls a candidate's export on every input, in a fresh worker with fuel and a
%% deadline. An input is one integer, for a one-argument function, or the
%% list of arguments, such as `[2147483647, 1]' for `f(i32, i32)'.
%%
%% Each candidate gets its own `wasm_instance_worker', with `isolation => fresh'
%% so that no state survives from one call to the next. Every call has a fuel
%% budget (work) and a deadline (time). Fuel stops a loop; the deadline is the
%% backstop, and when it passes the worker is killed and a new one takes over
%% for the remaining inputs. After `?MAX_TIMEOUTS' deadlines the remaining
%% inputs are reported as not run, so a module that hangs cannot hold the run
%% for long.
-module(wb_exec).

-export([run/3, run/4, limits/0]).

-export_type([outcome/0, input/0]).

%% The reference implementation uses about 20 instructions; 10,000 leaves a
%% candidate written very differently plenty of room.
-define(FUEL, 10_000).
-define(DEADLINE_MS, 1_000).
-define(MAX_TIMEOUTS, 3).

-type input() :: integer() | [integer()].
-type outcome() :: {ok, integer()}
                 | {error, wasm_error:error() | map()}
                 | not_run.

-spec limits() -> #{fuel := pos_integer(), deadline_ms := pos_integer()}.
limits() ->
    #{fuel => ?FUEL, deadline_ms => ?DEADLINE_MS}.

-spec run(wasm:module_(), binary(), [input()]) ->
          {ok, [{input(), outcome()}]} | {error, {instantiate, term()}}.
run(Module, Export, Inputs) ->
    run(Module, Export, Inputs, #{}).

%% `Opts' may override `fuel' and `deadline_ms'; the tests use it to reach the
%% deadline path.
-spec run(wasm:module_(), binary(), [input()], map()) ->
          {ok, [{input(), outcome()}]} | {error, {instantiate, term()}}.
run(Module, Export, Inputs, Opts) ->
    Cfg = maps:merge(limits(), Opts),
    Parent = self(),
    Ref = make_ref(),
    %% The worker is linked to the process that starts it, and a worker killed
    %% at a deadline takes an unprotected caller with it. This process traps
    %% exits so the runner does not.
    {Pid, MRef} = spawn_monitor(fun() ->
                                    process_flag(trap_exit, true),
                                    Parent ! {Ref, calls(Module, Export, Inputs, Cfg)}
                                end),
    receive
        {Ref, Result} ->
            erlang:demonitor(MRef, [flush]),
            Result;
        {'DOWN', MRef, process, Pid, Reason} ->
            error({wb_exec_crashed, Reason})
    end.

calls(Module, Export, Inputs, Cfg) ->
    case instantiates(Module, Cfg) of
        ok -> start_and_call(Module, Export, Inputs, Cfg);
        {error, Why} -> {error, {instantiate, Why}}
    end.

%% The worker instantiates the module after it has started, so a module that
%% cannot be instantiated shows up as a worker that dies on every call. Trying
%% once here first reports the reason instead. No guest code runs: the profile
%% allows no start function.
instantiates(Module, #{fuel := Fuel}) ->
    case wasm:instantiate(Module, #{}, wasm_limits:merge(wasm_limits:untrusted(), #{fuel => Fuel})) of
        {ok, Inst} -> wasm:destroy(Inst);
        {error, _} = E -> E
    end.

start_and_call(Module, Export, Inputs, Cfg) ->
    case start(Module, Cfg) of
        {ok, W} ->
            {Results, Last} = loop(Inputs, W, Export, Cfg#{module => Module}, 0, []),
            stop(Last),
            {ok, Results};
        {error, Why} ->
            {error, {instantiate, Why}}
    end.

start(Module, #{fuel := Fuel}) ->
    Limits = wasm_limits:merge(wasm_limits:untrusted(), #{fuel => Fuel}),
    case wasm_instance_worker:start_link(Module, #{limits => Limits, isolation => fresh}) of
        {ok, W} ->
            {ok, W};
        {error, _} = E ->
            flush_exits(),
            E
    end.

stop(none) ->
    ok;
stop(W) ->
    try wasm_instance_worker:stop(W)
    catch exit:_ -> ok      % already gone
    end,
    flush_exits().

loop([], W, _Export, _Cfg, _Timeouts, Acc) ->
    {lists:reverse(Acc), W};
loop([X | Rest], W, Export, #{deadline_ms := Deadline} = Cfg, Timeouts, Acc) ->
    case wasm_instance_worker:call(W, Export, args(X), Deadline) of
        {ok, [V]} ->
            loop(Rest, W, Export, Cfg, Timeouts, [{X, {ok, V}} | Acc]);
        {ok, Other} ->
            Err = #{class => interface, kind => result_count, results => Other},
            loop(Rest, W, Export, Cfg, Timeouts, [{X, {error, Err}} | Acc]);
        {error, #{kind := Kind} = Err} when Kind =:= timeout; Kind =:= worker_died ->
            %% The worker is gone. Start another for the inputs left.
            flush_exits(),
            restart(Rest, Export, Cfg, Timeouts + 1, [{X, {error, Err}} | Acc]);
        {error, Err} ->
            loop(Rest, W, Export, Cfg, Timeouts, [{X, {error, Err}} | Acc])
    end.

restart(Rest, _Export, _Cfg, Timeouts, Acc) when Rest =:= []; Timeouts >= ?MAX_TIMEOUTS ->
    {lists:reverse(Acc, [{X, not_run} || X <- Rest]), none};
restart(Rest, Export, #{module := Module} = Cfg, Timeouts, Acc) ->
    case start(Module, Cfg) of
        {ok, W} -> loop(Rest, W, Export, Cfg, Timeouts, Acc);
        {error, _} -> {lists:reverse(Acc, [{X, not_run} || X <- Rest]), none}
    end.

args(Args) when is_list(Args) -> Args;
args(X) -> [X].

flush_exits() ->
    receive
        {'EXIT', _, _} -> flush_exits()
    after 0 ->
        ok
    end.
