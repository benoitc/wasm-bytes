%% The two-engine comparison without running anything: scoring, the report
%% and the run record, from rows and comparisons written out here.
-module(wb_compare_tests).

-include_lib("eunit/include/eunit.hrl").

-define(HASH, ~"5085ed49ca1c432946f77ed39efe794a68d5e1622ee3edf67f85f5abaa37dee7").

all_match_test() ->
    Rows = [{1, 0, {ok, 0}, {ok, 0}}, {429, 1, {ok, 1}, {ok, 1}}],
    ?assertEqual(#{erlang_matches => 2, wasmtime_matches => 2, agree => 2,
                   first_discrepancy => none, verdict => pass},
                 wb_compare:summarize(Rows)).

engines_differ_test() ->
    Rows = [{1, 0, {ok, 0}, {ok, 0}}, {2, 1, {ok, 1}, {ok, 0}}, {3, 0, {ok, 0}, {ok, 0}}],
    ?assertMatch(#{verdict := engines_differ, agree := 2, erlang_matches := 3,
                   wasmtime_matches := 2,
                   first_discrepancy := #{input := 2, reference := 1,
                                          erlang_wasm := {ok, 1}, wasmtime := {ok, 0}}},
                 wb_compare:summarize(Rows)).

reference_differs_test() ->
    Rows = [{599, 1, {ok, 0}, {ok, 0}}],
    ?assertMatch(#{verdict := reference_differs, agree := 1, erlang_matches := 0},
                 wb_compare:summarize(Rows)).

%% Two failed calls agree, whatever each engine gives as the reason; a value
%% and a failure do not.
failures_agree_test() ->
    Rows = [{-1, 0, {error, ~"exhaustion/out_of_fuel"}, {error, ~"wasm trap: all fuel consumed"}},
            {-2, 0, {rejected, invalid}, {error, ~"type mismatch"}}],
    ?assertMatch(#{verdict := reference_differs, agree := 2}, wb_compare:summarize(Rows)),
    ?assertMatch(#{verdict := engines_differ, agree := 0},
                 wb_compare:summarize([{-1, 0, {ok, 0}, {error, ~"trap"}}])).

comparison() ->
    #{task => write, reply => ~"trials/write/claude-sonnet-5-5-1/reply.txt",
      module_bytes => 54, module_sha256 => ?HASH, inputs => 2,
      erlang_wasm => #{version => ~"0.11.0", verdict => pass, received_sha256 => ?HASH,
                       matches => 2},
      wasmtime => #{version => ~"50.0.1", received_sha256 => ?HASH, matches => 2},
      agree => 2, first_discrepancy => none, verdict => pass,
      host => #{os => ~"Debian GNU/Linux 13 (trixie)", kernel => ~"Linux 7.2.12",
                arch => ~"x86_64", otp => ~"29.1.2", erts => ~"17.1.1",
                note => ~"Linux container, CPU emulated"},
      recorded_on => ~"2026-11-23"}.

report_pass_test() ->
    Text = iolist_to_binary(wb_compare:report(comparison())),
    [?assertNotEqual(nomatch, binary:match(Text, Part))
     || Part <- [<<"module       54 bytes, sha256 ", ?HASH/binary>>,
                 ~"host         Debian GNU/Linux 13 (trixie), x86_64; Erlang/OTP 29.1.2 (Linux container, CPU emulated)",
                 ~"erlang_wasm  0.11.0, received the same bytes: 2 of 2 match the reference",
                 ~"first diff   none",
                 ~"verdict      pass"]].

report_failure_test() ->
    C = (comparison())#{
          erlang_wasm => #{version => ~"0.11.0", verdict => invalid,
                           received_sha256 => ~"00ff", matches => 0},
          first_discrepancy => #{input => -5, reference => 0,
                                 erlang_wasm => {rejected, invalid},
                                 wasmtime => {error, ~"type mismatch"}},
          verdict => reference_differs},
    Text = iolist_to_binary(wb_compare:report(C)),
    [?assertNotEqual(nomatch, binary:match(Text, Part))
     || Part <- [~"received DIFFERENT bytes, sha256 00ff",
                 ~"; checker verdict invalid: 0 of 2 match",
                 ~"input -5: reference 0, erlang_wasm rejected (invalid), wasmtime error (type mismatch)",
                 ~"verdict      reference_differs"]].

record_test() ->
    Dir = wb_test_io:scratch("compare-record"),
    Path = wb_compare:record(comparison(), Dir),
    ?assertEqual(filename:join([Dir, "write-claude-sonnet-5-5-1", "linux-x86_64.config"]), Path),
    {ok, Terms} = file:consult(Path),
    ?assertEqual(?HASH, proplists:get_value(module_sha256, Terms)),
    ?assertEqual(pass, proplists:get_value(verdict, Terms)),
    ?assertMatch(#{note := _}, proplists:get_value(host, Terms)).

%% A reply outside trials/ and examples/ is named after its file.
record_outside_trials_test() ->
    Dir = wb_test_io:scratch("compare-record-outside"),
    Path = wb_compare:record((comparison())#{reply => ~"/tmp/mine/attempt.txt"}, Dir),
    ?assertEqual(filename:join([Dir, "attempt", "linux-x86_64.config"]), Path).
