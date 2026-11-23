-module(wb_task_tests).

-include_lib("eunit/include/eunit.hrl").

inputs_cover_statuses_and_boundaries_test() ->
    Inputs = wb_task:inputs(write),
    ?assertEqual(lists:usort(Inputs), Inputs),
    ?assert(lists:all(fun(X) -> lists:member(X, Inputs) end, lists:seq(100, 599))),
    [?assert(lists:member(X, Inputs))
     || X <- [-2147483648, 2147483647, -1, 0, 99, 600, 1000]],
    ?assert(lists:all(fun(X) -> X >= -2147483648 andalso X =< 2147483647 end, Inputs)).

write_reference_test() ->
    Cases = [{428, 0}, {429, 1}, {430, 0}, {408, 0}, {499, 0}, {500, 1}, {501, 1},
             {599, 1}, {600, 0}, {-429, 0}, {-500, 0}, {0, 0},
             {-2147483648, 0}, {2147483647, 0}, {429 + 65536, 0}],
    [?assertEqual({X, Want}, {X, wb_task:expected(write, X)}) || {X, Want} <- Cases].

revise_reference_test() ->
    Cases = [{407, 0}, {408, 1}, {409, 0}, {429, 1}, {500, 1}, {501, 0}, {502, 1},
             {599, 1}, {600, 0}, {-408, 0}, {-501, 0}, {408 + 65536, 0}],
    [?assertEqual({X, Want}, {X, wb_task:expected(revise, X)}) || {X, Want} <- Cases].

digits_reference_test() ->
    Cases = [{0, 0}, {7, 7}, {10, 1}, {907, 16}, {-907, 16}, {1234567890, 45},
             {-1234567890, 45}, {2147483647, 46}, {-2147483647, 46}, {-2147483648, 47},
             {999999999, 81}, {1999999999, 82}],
    [?assertEqual({X, Want}, {X, wb_task:expected(digits, X)}) || {X, Want} <- Cases].

digits_inputs_cover_the_awkward_values_test() ->
    Inputs = wb_task:inputs(digits),
    ?assertEqual(lists:usort(Inputs), Inputs),
    ?assert(lists:all(fun(X) -> lists:member(X, Inputs) end, lists:seq(0, 1000))),
    [?assert(lists:member(X, Inputs))
     || X <- [-2147483648, 2147483647, -1, -100, 999999999, 1000000000, -1000000000]],
    ?assert(lists:all(fun(X) -> X >= -2147483648 andalso X =< 2147483647 end, Inputs)),
    %% The spread is fixed: the same 200 values on every Erlang release.
    ?assertEqual(1353, length(Inputs)).

the_change_request_changes_two_inputs_test() ->
    ?assertEqual([{408, 0, 1}, {501, 1, 0}], wb_task:intended_changes()).
