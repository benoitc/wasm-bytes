%% Calls a module's export through the Wasmtime command line, one input per
%% process, with Wasmtime's own fuel and time limits.
%%
%% Wasmtime is optional. Nothing else in the runner needs it; `find/0' says
%% whether it is there. `WASMTIME' names the executable when it is not on the
%% path.
-module(wb_wasmtime).

-export([find/0, version/1, run/4, run/5, parse/2]).

-define(FUEL, "fuel=10000").
-define(TIMEOUT, "timeout=1s").
%% Wasmtime stops a call after a second; this is the backstop if it does not.
-define(KILL_AFTER_MS, 10_000).
-define(PARALLEL, 8).

-spec find() -> {ok, file:filename()} | {error, not_found}.
find() ->
    case os:getenv("WASMTIME") of
        Path when is_list(Path), Path =/= "" ->
            case filelib:is_regular(Path) of
                true -> {ok, Path};
                false -> {error, not_found}
            end;
        _ ->
            case os:find_executable("wasmtime") of
                false -> {error, not_found};
                Path -> {ok, Path}
            end
    end.

%% `"50.0.1"' from `wasmtime 50.0.1 (...)'.
-spec version(file:filename()) -> binary().
version(Exe) ->
    {0, Out} = exec(Exe, ["--version"]),
    case string:split(string:trim(Out), " ", all) of
        [_, V | _] -> V;
        _ -> string:trim(Out)
    end.

%% `[{Input, {ok, Value} | {error, Why}}]', in the order of `Inputs'.
-spec run(file:filename(), file:filename(), binary(), [wb_exec:input()]) ->
          [{wb_exec:input(), {ok, integer()} | {error, binary()}}].
run(Exe, Wasm, Export, Inputs) ->
    run(Exe, Wasm, Export, Inputs, #{}).

%% `Limits' may raise the fuel and the deadline, as a case with long-running
%% calls does; the default is the runner's 10,000 fuel and one second.
-spec run(file:filename(), file:filename(), binary(), [wb_exec:input()], map()) ->
          [{wb_exec:input(), {ok, integer()} | {error, binary()}}].
run(Exe, Wasm, Export, Inputs, Limits) ->
    put(wb_wasmtime_limits, Limits),
    Indexed = lists:enumerate(Inputs),
    Chunks = chunks(Indexed, ?PARALLEL),
    Parent = self(),
    Refs = [begin
                Ref = make_ref(),
                spawn_link(fun() ->
                               put(wb_wasmtime_limits, Limits),
                               Parent ! {Ref, [{I, X, call(Exe, Wasm, Export, X)} || {I, X} <- Chunk]}
                           end),
                Ref
            end || Chunk <- Chunks],
    Results = lists:append([receive {Ref, R} -> R end || Ref <- Refs]),
    [{X, O} || {_, X, O} <- lists:keysort(1, Results)].

chunks(List, N) ->
    [[E || {J, E} <- lists:enumerate(List), J rem N =:= K] || K <- lists:seq(0, N - 1)].

call(Exe, Wasm, Export, X) ->
    Limits = case get(wb_wasmtime_limits) of undefined -> #{}; L -> L end,
    Fuel = case Limits of #{fuel := F} -> "fuel=" ++ integer_to_list(F); _ -> ?FUEL end,
    Timeout = case Limits of #{deadline_ms := D} -> "timeout=" ++ integer_to_list(D) ++ "ms"; _ -> ?TIMEOUT end,
    Args = ["run", "-W", Fuel, "-W", Timeout, "--invoke", binary_to_list(Export),
            Wasm | [integer_to_list(A) || A <- args(X)]],
    case exec(Exe, Args) of
        {timeout, _} -> {error, ~"no answer within 10 s; the process was abandoned"};
        {Status, Out} -> parse(Status, Out)
    end.

args(Args) when is_list(Args) -> Args;
args(X) -> [X].

%% Wasmtime prints the result on its own line, and on stderr a warning that
%% `--invoke' is experimental. An i32 result is read as signed, as erlang_wasm
%% returns it.
-spec parse(integer(), binary()) -> {ok, integer()} | {error, binary()}.
parse(Status, Out) ->
    Lines = [L || L <- string:split(Out, "\n", all), L =/= <<>>,
                  not lists:prefix("warning:", binary_to_list(L))],
    case {Status, Lines} of
        {0, [Line]} ->
            try binary_to_integer(string:trim(Line)) of
                V when V > 2147483647 -> {ok, V - 4294967296};
                V -> {ok, V}
            catch
                error:badarg -> {error, Line}
            end;
        _ ->
            {error, reason(Lines)}
    end.

%% The line that says why: the trap, or else the last line printed.
reason(Lines) ->
    case [L || L <- Lines, binary:match(L, ~"wasm trap:") =/= nomatch] of
        [Trap | _] -> frame_free(Trap);
        [] when Lines =/= [] -> frame_free(lists:last(Lines));
        [] -> ~"exited with no output"
    end.

%% `2: wasm trap: ...' is a backtrace line; the number is the frame.
frame_free(Line) ->
    string:trim(re:replace(Line, "^\\s*[0-9]+:\\s*", "", [{return, binary}])).

exec(Exe, Args) ->
    Port = open_port({spawn_executable, Exe},
                     [{args, Args}, exit_status, stderr_to_stdout, binary, hide]),
    collect(Port, []).

collect(Port, Acc) ->
    receive
        {Port, {data, D}} ->
            collect(Port, [D | Acc]);
        {Port, {exit_status, S}} ->
            {S, iolist_to_binary(lists:reverse(Acc))}
    after ?KILL_AFTER_MS ->
        try port_close(Port) catch error:badarg -> ok end,
        {timeout, iolist_to_binary(lists:reverse(Acc))}
    end.
