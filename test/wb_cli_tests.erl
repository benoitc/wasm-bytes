%% The command line, through `wasm_bytes:run/2': each command's exit status
%% and the lines a reader relies on.
-module(wb_cli_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SONNET, "trials/write/claude-sonnet-5-5-1").

cli_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"check write: a pass exits 0", fun check_pass/0},
      {"check write: a wrong answer exits 1 and names the input", fun check_wrong/0},
      {"check digits: a pass exits 0", fun check_digits/0},
      {"check revise: either argument order", fun check_revise/0},
      {"check revise: a base that fails task 1 is refused", fun check_revise_refused/0},
      {"prompt: each prompt is printed as saved", fun prompts/0},
      {"prompt revise: renders the base, refuses a failing one", fun prompt_revise/0},
      {"trace: prints the trial and writes the module", fun trace/0},
      {"trace: a reply that is not hex writes no module", fun trace_not_hex/0},
      {"trace: a directory without a prompt exits 2", fun trace_missing/0},
      {"replay exits 0", {timeout, 60, fun replay/0}},
      {"help prints the usage", fun help/0},
      {"an unknown command, a bad task or a missing file exits 2", fun errors/0},
      {"compare: without Wasmtime it exits 2 and says so", fun compare_no_wasmtime/0},
      {"compare: a reply that is not hex exits 2", fun compare_not_hex/0}
      | compare_with_wasmtime()]}.

run(Args) ->
    Err = wb_test_io:device(),
    {Code, Out} = wb_test_io:capture(fun() -> wasm_bytes:run(Args, Err) end),
    {Code, Out, wb_test_io:text(Err)}.

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

file(Path) ->
    {ok, Bin} = file:read_file(filename:join(wb_test_io:root(), Path)),
    Bin.

check_pass() ->
    {Code, Out, _} = run(["check", "write", ?SONNET "/reply.txt"]),
    ?assertEqual(0, Code),
    ?assert(has(Out, ~"528 of 528 match the reference")),
    ?assert(has(Out, ~"verdict  pass")).

check_wrong() ->
    {Code, Out, _} = run(["check", "write", "examples/write/misses-599/reply.txt"]),
    ?assertEqual(1, Code),
    ?assert(has(Out, ~"input 599: expected 1, got 0")).

check_digits() ->
    {Code, Out, _} = run(["check", "digits", "trials/digits/claude-haiku-5-5-1/reply.txt"]),
    ?assertEqual(0, Code),
    ?assert(has(Out, ~"1353 of 1353 match the reference")).

check_revise() ->
    Base = "examples/write/accepted/reply.txt",
    Revised = "examples/revise/accepted/reply.txt",
    {0, Out1, _} = run(["check", "revise", Revised, "--base", Base]),
    {0, Out2, _} = run(["check", "revise", "--base", Base, Revised]),
    ?assertEqual(Out1, Out2),
    ?assert(has(Out1, ~"request  done: 408 0 -> 1, 501 1 -> 0")).

check_revise_refused() ->
    {Code, Out, _} = run(["check", "revise", "examples/revise/accepted/reply.txt",
                          "--base", "examples/write/misses-599/reply.txt"]),
    ?assertEqual(1, Code),
    ?assert(has(Out, ~"does not pass task 1")).

prompts() ->
    [begin
         {0, Out, _} = run(Args),
         ?assertEqual({Args, file(File)}, {Args, Out})
     end || {Args, File} <- [{["prompt", "write"], "prompts/write.txt"},
                             {["prompt", "write", "--guided"], "prompts/write.guided.txt"},
                             {["prompt", "digits"], "prompts/digits.txt"},
                             {["prompt", "digits", "--guided"], "prompts/digits.guided.txt"}]].

prompt_revise() ->
    {0, Out, _} = run(["prompt", "revise", "--base", "examples/write/accepted/reply.txt"]),
    ?assertEqual(file("prompts/revise.example.txt"), Out),
    {1, <<>>, Err} = run(["prompt", "revise", "--base", "examples/write/misses-599/reply.txt"]),
    ?assert(has(Err, ~"does not pass task 1")).

trace() ->
    Wasm = filename:join(wb_test_io:scratch("cli-trace"), "module.wasm"),
    {0, Out, _} = run(["trace", ?SONNET, "--wasm", Wasm]),
    ?assert(has(Out, ~"module.sha256 holds the same hash")),
    ?assert(has(Out, ~"  wrote      ")),
    {ok, Bytes} = file:read_file(Wasm),
    ?assertEqual(54, byte_size(Bytes)),
    ?assertEqual(wb_trace:recorded_sha256(filename:join(wb_test_io:root(), ?SONNET)),
                 wb_trace:sha256(Bytes)),
    {0, Plain, _} = run(["trace", ?SONNET]),
    ?assertNot(has(Plain, ~"  wrote      ")).

trace_not_hex() ->
    Dir = wb_test_io:scratch("cli-trace-not-hex"),
    ok = file:write_file(filename:join(Dir, "prompt.txt"), ~"the prompt"),
    ok = file:write_file(filename:join(Dir, "reply.txt"), ~"Here it is: 00 61"),
    Wasm = filename:join(Dir, "module.wasm"),
    {1, Out, _} = run(["trace", Dir, "--wasm", Wasm]),
    ?assert(has(Out, ~"the reply is not hex")),
    ?assertNot(filelib:is_file(Wasm)).

trace_missing() ->
    {2, _, Err} = run(["trace", wb_test_io:scratch("cli-trace-empty")]),
    ?assert(has(Err, ~"cannot read")).

replay() ->
    {0, Out, _} = run(["replay"]),
    ?assert(has(Out, ~"[model trial] trials/write/claude-sonnet-5-5-1")).

help() ->
    {0, Out, _} = run(["help"]),
    ?assertMatch(<<"usage: bin/wasm-bytes replay", _/binary>>, Out).

errors() ->
    {2, _, E1} = run(["frob"]),
    ?assert(has(E1, ~"unknown command")),
    ?assert(has(E1, ~"usage:")),
    {2, _, E2} = run(["compare", "rewrite", ?SONNET "/reply.txt"]),
    ?assert(has(E2, ~"the task is write, revise, digits, pan or reverse")),
    {2, _, E3} = run(["check", "write", "no/such/reply.txt"]),
    ?assert(has(E3, ~"cannot read no/such/reply.txt")).

compare_no_wasmtime() ->
    with_env("WASMTIME", "/no/such/wasmtime",
             fun() ->
                 {2, _, Err} = run(["compare", "write", ?SONNET "/reply.txt"]),
                 ?assert(has(Err, ~"wasmtime not found"))
             end).

compare_not_hex() ->
    {2, _, Err} = run(["compare", "write", "examples/write/prose-around-hex/reply.txt"]),
    %% Without Wasmtime the command stops before reading the hex.
    ?assert(has(Err, ~"the reply is not hex") orelse has(Err, ~"wasmtime not found")).

compare_with_wasmtime() ->
    case wb_wasmtime:find() of
        {ok, _} ->
            [{"compare: a pass exits 0 and --record writes the run",
              {timeout, 120, fun compare_record/0}},
             {"compare: a wrong module exits 1", {timeout, 120, fun compare_wrong/0}}];
        {error, not_found} ->
            [{"wasmtime is not installed: the compare runs are skipped", fun() -> ok end}]
    end.

compare_record() ->
    Dir = wb_test_io:scratch("cli-record"),
    %% An absolute path inside the repository is named as the repository
    %% names it.
    Reply = filename:join(wb_test_io:root(), ?SONNET "/reply.txt"),
    {0, Out, _} = run(["compare", "write", Reply, "--record", Dir]),
    ?assert(has(Out, <<"reply        " ?SONNET "/reply.txt">>)),
    [Record] = filelib:wildcard(filename:join([Dir, "write-claude-sonnet-5-5-1", "*.config"])),
    {ok, Terms} = file:consult(Record),
    ?assertEqual(pass, proplists:get_value(verdict, Terms)).

compare_wrong() ->
    {1, Out, _} = run(["compare", "write", "examples/write/misses-599/reply.txt"]),
    ?assert(has(Out, ~"first diff   input 599")).

with_env(Name, Value, F) ->
    Old = os:getenv(Name),
    os:putenv(Name, Value),
    try F()
    after
        case Old of
            false -> os:unsetenv(Name);
            _ -> os:putenv(Name, Old)
        end
    end.
