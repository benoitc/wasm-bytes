%% Stages of a check that the saved replies do not reach: the size limits,
%% a module that cannot be instantiated, and how each is reported.
-module(wb_check_tests).

-include_lib("eunit/include/eunit.hrl").

-import(wb_test_wasm, [module/1, retry_body/0, func_type/2]).

check_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(wasm), Apps end,
     fun(_) -> ok end,
     [{"a reply over 64 KiB is refused before decoding", fun text_too_large/0},
      {"a module over 4096 bytes is refused before erlang_wasm sees it", fun module_too_large/0},
      {"a module that cannot be instantiated is an execution failure",
       fun instantiation_fails/0},
      {"each hex error is reported with its position", fun hex_errors/0}]}.

report(R) ->
    iolist_to_binary(wb_report:report(R)).

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

text_too_large() ->
    R = wb_check:check(write, binary:copy(~"00 ", 22000)),
    ?assertMatch(#{verdict := too_large, why := {text, 66000, 65536}}, R),
    ?assert(has(report(R), ~"size     66000 bytes of reply; the limit is 65536")).

module_too_large() ->
    R = wb_check:check(write, iolist_to_binary(wb_hex:encode(binary:copy(<<0>>, 4097)))),
    ?assertMatch(#{verdict := too_large, why := {bytes, 4097, 4096}}, R),
    ?assert(has(report(R), ~"hex      4097 bytes; the limit is 4096")).

%% A table of one slot and an element segment written at slot 5: the module
%% validates and has the profile's shape, and instantiating it traps.
instantiation_fails() ->
    Bytes = module(#{type => [func_type([i32], [i32])], function => [<<0>>],
                     table => [<<16#70, 0, 1>>],
                     export => [<<5, "retry", 0, 0>>],
                     elem => [<<0, 16#41, 5, 16#0b, 1, 0>>],
                     code => [retry_body()]}),
    ?assertMatch({ok, _}, wasm:compile(Bytes)),
    R = wb_check:check(write, iolist_to_binary(wb_hex:encode(Bytes))),
    ?assertMatch(#{verdict := execution_failure, failures := [{instantiate, _}], results := []}, R),
    ?assert(has(report(R), ~"instantiation failed: ")).

hex_errors() ->
    [begin
         R = wb_check:check(write, Text),
         ?assertEqual({Text, malformed_hex}, {Text, maps:get(verdict, R)}),
         ?assert(has(report(R), Want))
     end || {Text, Want} <- [{~"", ~"malformed: no hex digits"},
                             {~"00 6", ~"line 1, column 4: a hex digit without its pair"},
                             {~"```", ~"line 1, column 1: a backtick is not a hex digit"},
                             {~"00\n  zz", ~"line 2, column 3: 'z' is not a hex digit"},
                             {<<"00 ", 16#c2, 16#a0>>, ~"line 1, column 4: U+00A0 is not a hex digit"}]].
