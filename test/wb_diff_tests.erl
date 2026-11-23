-module(wb_diff_tests).

-include_lib("eunit/include/eunit.hrl").

identical_test() ->
    ?assertEqual([], wb_diff:hunks(~"abcdef", ~"abcdef")).

insertion_test() ->
    ?assertEqual([#{base_at => 2, base => <<>>, revised_at => 2, revised => ~"XY"}],
                 wb_diff:hunks(~"abcd", ~"abXYcd")).

deletion_test() ->
    ?assertEqual([#{base_at => 1, base => ~"bc", revised_at => 1, revised => <<>>}],
                 wb_diff:hunks(~"abcd", ~"ad")).

replacement_test() ->
    ?assertEqual([#{base_at => 1, base => ~"b", revised_at => 1, revised => ~"Z"}],
                 wb_diff:hunks(~"abc", ~"aZc")).

empty_sides_test() ->
    ?assertEqual([#{base_at => 0, base => <<>>, revised_at => 0, revised => ~"ab"}],
                 wb_diff:hunks(<<>>, ~"ab")),
    ?assertEqual([#{base_at => 0, base => ~"ab", revised_at => 0, revised => <<>>}],
                 wb_diff:hunks(~"ab", <<>>)).

%% An inserted instruction that begins like the one after it is shown whole.
insertion_slides_to_the_instruction_start_test() ->
    Base = <<16#20, 0, 16#41, 16#ad, 3, 16#46>>,
    Revised = <<16#20, 0, 16#41, 16#98, 3, 16#46, 16#20, 0, 16#41, 16#ad, 3, 16#46>>,
    ?assertEqual([#{base_at => 0, base => <<>>, revised_at => 0,
                    revised => <<16#20, 0, 16#41, 16#98, 3, 16#46>>}],
                 wb_diff:hunks(Base, Revised)).

%% The hunks rebuild the revision, and the edit script is as short as the
%% longest common subsequence allows.
random_pairs_test_() ->
    {timeout, 60, fun random_pairs/0}.

random_pairs() ->
    rand:seed(exsss, {7, 8, 9}),
    [begin
         A = random_bytes(), B = random_bytes(),
         ?assertEqual(B, wb_diff:apply_hunks(A, wb_diff:hunks(A, B))),
         Edits = lists:sum([byte_size(X) || {Op, X} <- wb_diff:diff(A, B), Op =/= eq]),
         ?assertEqual(byte_size(A) + byte_size(B) - 2 * lcs(A, B), Edits)
     end || _ <- lists:seq(1, 300)].

%% A small alphabet, so that the two sides share a lot.
random_bytes() ->
    << <<(rand:uniform(4))>> || _ <- lists:seq(1, rand:uniform(40) - 1) >>.

lcs(A, B) ->
    As = binary_to_list(A),
    Row0 = lists:duplicate(byte_size(B) + 1, 0),
    lists:last(lists:foldl(fun(X, Prev) -> lcs_row(X, binary_to_list(B), Prev) end, Row0, As)).

lcs_row(X, Bs, [P0 | PrevRest]) ->
    lcs_row(X, Bs, P0, PrevRest, 0, [0]).

lcs_row(_X, [], _Diag, [], _Left, Acc) ->
    lists:reverse(Acc);
lcs_row(X, [Y | Ys], Diag, [Up | Ups], Left, Acc) ->
    V = case X =:= Y of
            true -> Diag + 1;
            false -> max(Up, Left)
        end,
    lcs_row(X, Ys, Up, Ups, V, [V | Acc]).
