-module(wb_profile_tests).

-include_lib("eunit/include/eunit.hrl").

-import(wb_test_wasm, [module/1, retry_body/0, func_type/2]).

retry_export() ->
    [<<5, "retry", 0, 0>>].

accepted() ->
    module(#{type => [func_type([i32], [i32])], function => [<<0>>],
             export => retry_export(), code => [retry_body()]}).

%% Every module here must be one erlang_wasm accepts: the profile is only ever
%% checked after `wasm:compile/1'.
profile(Bytes) ->
    ?assertMatch({ok, _}, wasm:compile(Bytes)),
    wb_profile:check(Bytes, write).

accepted_test() ->
    ?assertEqual(ok, profile(accepted())).

import_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])],
                     import => [<<3, "env", 1, "f", 0, 0>>],
                     function => [<<0>>],
                     export => [<<5, "retry", 0, 1>>], code => [retry_body()]}),
    ?assertEqual({error, [{imports, 1}]}, profile(Bytes)).

memory_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])], function => [<<0>>],
                     memory => [<<0, 1>>],
                     export => retry_export(), code => [retry_body()]}),
    ?assertEqual({error, [{memories, 1}]}, profile(Bytes)).

start_function_test() ->
    %% A start function must take nothing and return nothing, so it is a second
    %% function, and the profile reports both.
    Bytes = module(#{type => [func_type([i32], [i32]), func_type([], [])],
                     function => [<<0>>, <<1>>],
                     export => retry_export(), start => 1,
                     code => [retry_body(), <<2, 0, 16#0b>>]}),
    ?assertEqual({error, [start_function, {defined_functions, 2}]}, profile(Bytes)).

two_functions_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])], function => [<<0>>, <<0>>],
                     export => retry_export(), code => [retry_body(), retry_body()]}),
    ?assertEqual({error, [{defined_functions, 2}]}, profile(Bytes)).

no_function_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])]}),
    ?assertEqual({error, [{defined_functions, 0}, {missing_export, ~"retry"}]}, profile(Bytes)).

wrong_name_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])], function => [<<0>>],
                     export => [<<5, "Retry", 0, 0>>], code => [retry_body()]}),
    ?assertEqual({error, [{missing_export, ~"retry"}, {unexpected_exports, [~"Retry"]}]},
                 profile(Bytes)).

wrong_result_type_test() ->
    Body = <<0, 16#42, 1, 16#0b>>,                       % i64.const 1
    Bytes = module(#{type => [func_type([i32], [i64])], function => [<<0>>],
                     export => retry_export(), code => [[byte_size(Body), Body]]}),
    ?assertEqual({error, [{signature, ~"retry", {[i32], [i32]}, {[i32], [i64]}}]},
                 profile(Bytes)).

export_not_a_function_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])], function => [<<0>>],
                     global => [<<16#7f, 0, 16#41, 0, 16#0b>>],
                     export => [<<5, "retry", 3, 0>>], code => [retry_body()]}),
    ?assertEqual({error, [{export_not_a_function, ~"retry", global}]}, profile(Bytes)).

extra_export_test() ->
    Bytes = module(#{type => [func_type([i32], [i32])], function => [<<0>>],
                     export => [<<5, "retry", 0, 0>>, <<4, "also", 0, 0>>],
                     code => [retry_body()]}),
    ?assertEqual({error, [{unexpected_exports, [~"also"]}]}, profile(Bytes)).

every_violation_has_text_test() ->
    Vs = [{imports, 1}, {memories, 2}, start_function, {defined_functions, 0},
          {missing_export, ~"retry"}, {export_not_a_function, ~"retry", table},
          {signature, ~"retry", {[i32], [i32]}, {[i64], [i32]}},
          {signature_unreadable, ~"retry", oops}, {unexpected_exports, [~"a", ~"b"]}],
    [?assert(iolist_size(wb_profile:format_violation(V)) > 0) || V <- Vs].
