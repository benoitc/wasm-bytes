%% The evidence behind the three claims: the trace from prompt to bytes, the
%% replay of five outcomes, the two-engine comparison and the run records.
%% The Wasmtime cases are skipped, and say so, when Wasmtime is not installed.
-module(wb_evidence_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SONNET, "trials/write/claude-sonnet-5-5-1").

root() ->
    {ok, Cwd} = file:get_cwd(),
    Cwd.

evidence_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"each trial's module.sha256 is the hash of its decoded reply", fun recorded_hashes/0},
      {"the trace shows the prompt, the reply and the 54 bytes", fun trace/0},
      {"the replay gives each outcome its expected verdict", {timeout, 60, fun replay/0}},
      {"Wasmtime output is read as erlang_wasm reports values", fun parse/0},
      {"run records are for the recorded module and pass", fun records/0}
      | wasmtime_cases()]}.

recorded_hashes() ->
    Dirs = filelib:wildcard(filename:join([root(), "trials", "*", "*", "reply.txt"])),
    ?assert(length(Dirs) >= 5),
    [begin
         Dir = filename:dirname(Reply),
         {ok, Text} = file:read_file(Reply),
         Want = case wb_hex:decode(Text) of
                    {ok, Bytes} -> wb_trace:sha256(Bytes);
                    {error, _} -> missing      % no module, so no hash
                end,
         ?assertEqual({Dir, Want}, {Dir, wb_trace:recorded_sha256(Dir)})
     end || Reply <- Dirs].

trace() ->
    {ok, T} = wb_trace:load(filename:join(root(), ?SONNET)),
    #{prompt := Prompt, decoded := {ok, Bytes}} = T,
    {ok, Write} = file:read_file(filename:join([root(), "prompts", "write.txt"])),
    ?assertEqual(Write, Prompt),
    ?assertEqual(54, byte_size(Bytes)),
    Out = iolist_to_binary(wb_trace:trace(T)),
    [?assertNotEqual(nomatch, binary:match(Out, Needle))
     || Needle <- [~"  |   retry(x) returns 1 when x is 429,",
                   ~"  | 0a 15 01 13 00 20 00 41 ad 03 46",
                   ~"code section, 21 bytes follow",
                   ~"module.sha256 holds the same hash"]].

replay() ->
    {Out, Ok} = wb_replay:run(root()),
    ?assert(Ok),
    Text = iolist_to_binary(Out),
    [?assertNotEqual(nomatch, binary:match(Text, atom_to_binary(V))) || {_, _, V} <- wb_replay:cases()],
    ?assertEqual(4, length(binary:matches(Text, ~"[constructed]"))),
    ?assertEqual(1, length(binary:matches(Text, ~"[model trial]"))).

parse() ->
    Warn = ~"warning: using `--invoke` with a function that takes arguments is experimental\n",
    ?assertEqual({ok, 1}, wb_wasmtime:parse(0, <<Warn/binary, "1\n">>)),
    ?assertEqual({ok, -1}, wb_wasmtime:parse(0, ~"4294967295\n")),
    ?assertEqual({error, ~"wasm trap: all fuel consumed by WebAssembly"},
                 wb_wasmtime:parse(134, <<"Error: failed to run\n    0: 0x2d - <unknown>!<wasm function 0>\n"
                                          "    2: wasm trap: all fuel consumed by WebAssembly\n">>)),
    ?assertMatch({error, _}, wb_wasmtime:parse(0, ~"not a number\n")).

%% Whatever records evidence/runs holds, each one ran the recorded Sonnet
%% module and passed in both engines.
records() ->
    Want = wb_trace:recorded_sha256(filename:join(root(), ?SONNET)),
    [begin
         {ok, Terms} = file:consult(Path),
         R = maps:from_list(Terms),
         ?assertEqual({Path, Want}, {Path, maps:get(module_sha256, R)}),
         ?assertEqual({Path, pass}, {Path, maps:get(verdict, R)}),
         #{erlang_wasm := #{received_sha256 := E}, wasmtime := #{received_sha256 := W}} = R,
         ?assertEqual({Path, Want, Want}, {Path, E, W})
     end || Path <- filelib:wildcard(filename:join([root(), "evidence", "runs", "*.config"]))].

wasmtime_cases() ->
    case wb_wasmtime:find() of
        {ok, _} ->
            [{"both engines answer all 528 inputs for the Sonnet module", {timeout, 120, fun compare_pass/0}},
             {"a wrong module is reported at its first wrong input", {timeout, 120, fun compare_wrong/0}}];
        {error, not_found} ->
            [{"wasmtime is not installed: the two-engine cases are skipped", fun() -> ok end}]
    end.

compare_pass() ->
    {ok, Text} = file:read_file(filename:join([root(), ?SONNET, "reply.txt"])),
    {ok, C} = wb_compare:compare(write, Text, ~"sonnet"),
    Hash = wb_trace:recorded_sha256(filename:join(root(), ?SONNET)),
    ?assertMatch(#{verdict := pass, inputs := 528, agree := 528, first_discrepancy := none,
                   module_sha256 := Hash,
                   erlang_wasm := #{matches := 528, received_sha256 := Hash},
                   wasmtime := #{matches := 528, received_sha256 := Hash}}, C).

compare_wrong() ->
    {ok, Text} = file:read_file(filename:join([root(), "examples", "write", "misses-599", "reply.txt"])),
    {ok, C} = wb_compare:compare(write, Text, ~"misses-599"),
    ?assertMatch(#{verdict := reference_differs, agree := 528,
                   first_discrepancy := #{input := 599, reference := 1,
                                          erlang_wasm := {ok, 0}, wasmtime := {ok, 0}}}, C).
