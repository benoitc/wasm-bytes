%% Finding Wasmtime. These run whether or not Wasmtime is installed.
-module(wb_wasmtime_tests).

-include_lib("eunit/include/eunit.hrl").

with_env(Value, F) ->
    Old = os:getenv("WASMTIME"),
    case Value of
        false -> os:unsetenv("WASMTIME");
        _ -> os:putenv("WASMTIME", Value)
    end,
    try F()
    after
        case Old of
            false -> os:unsetenv("WASMTIME");
            _ -> os:putenv("WASMTIME", Old)
        end
    end.

%% WASMTIME names the executable; a path that is not a file is not found,
%% even when another Wasmtime is on the PATH.
named_by_variable_test() ->
    Exe = os:find_executable("erl"),
    with_env(Exe, fun() -> ?assertEqual({ok, Exe}, wb_wasmtime:find()) end),
    with_env("/no/such/wasmtime", fun() -> ?assertEqual({error, not_found}, wb_wasmtime:find()) end).

found_on_path_test() ->
    with_env(false, fun() ->
        case os:find_executable("wasmtime") of
            false -> ?assertEqual({error, not_found}, wb_wasmtime:find());
            Path -> ?assertEqual({ok, Path}, wb_wasmtime:find())
        end
    end).
