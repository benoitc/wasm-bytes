%% A byte diff between the module a model was given and the one it sent back.
%%
%% Myers' shortest edit script over the bytes, after the common prefix and
%% suffix are set aside, grouped into hunks. A hunk says where it is in both
%% modules, which bytes the base had there and which bytes the revision has.
%% Above `?MAX_EDITS' edits the middle is reported as one replacement: that is
%% a rewrite, and a finer diff of it would not be read.
-module(wb_diff).

-export([diff/2, hunks/2, apply_hunks/2]).

-export_type([op/0, hunk/0]).

-define(MAX_EDITS, 2048).

-type op() :: {eq | del | ins, binary()}.
-type hunk() :: #{base_at := non_neg_integer(), base := binary(),
                  revised_at := non_neg_integer(), revised := binary()}.

%% The edit script turning `A' into `B'.
-spec diff(binary(), binary()) -> [op()].
diff(A, B) ->
    P = binary:longest_common_prefix([A, B]),
    A1 = binary:part(A, P, byte_size(A) - P),
    B1 = binary:part(B, P, byte_size(B) - P),
    S = binary:longest_common_suffix([A1, B1]),
    A2 = binary:part(A1, 0, byte_size(A1) - S),
    B2 = binary:part(B1, 0, byte_size(B1) - S),
    Middle = case myers(A2, B2) of
                 {ok, Ops} -> Ops;
                 too_many -> [{del, A2}, {ins, B2}]
             end,
    slide(compact([{eq, binary:part(A, 0, P)}] ++ Middle ++
                  [{eq, binary:part(A1, byte_size(A1) - S, S)}])).

-spec hunks(binary(), binary()) -> [hunk()].
hunks(A, B) ->
    to_hunks(diff(A, B), 0, 0, []).

to_hunks([], _AAt, _BAt, Acc) ->
    lists:reverse(Acc);
to_hunks([{eq, Bin} | Rest], AAt, BAt, Acc) ->
    to_hunks(Rest, AAt + byte_size(Bin), BAt + byte_size(Bin), Acc);
to_hunks(Ops, AAt, BAt, Acc) ->
    {Changed, Rest} = lists:splitwith(fun({Op, _}) -> Op =/= eq end, Ops),
    Del = << <<X/binary>> || {del, X} <- Changed >>,
    Ins = << <<X/binary>> || {ins, X} <- Changed >>,
    H = #{base_at => AAt, base => Del, revised_at => BAt, revised => Ins},
    to_hunks(Rest, AAt + byte_size(Del), BAt + byte_size(Ins), [H | Acc]).

%% Rebuilds the revision from the base and the hunks. The tests use it to
%% check that the diff says everything there is to say.
-spec apply_hunks(binary(), [hunk()]) -> binary().
apply_hunks(A, Hunks) ->
    apply_hunks(A, 0, Hunks, []).

apply_hunks(A, At, [], Acc) ->
    iolist_to_binary(lists:reverse(Acc, [binary:part(A, At, byte_size(A) - At)]));
apply_hunks(A, At, [#{base_at := HAt, base := Del, revised := Ins} | Rest], Acc) ->
    Same = binary:part(A, At, HAt - At),
    apply_hunks(A, HAt + byte_size(Del), Rest, [Ins, Same | Acc]).

%% Moves each pure insertion or deletion as far left as it can go without
%% changing what it does. An inserted instruction that starts with the same
%% bytes as the one after it is then shown whole, `20 00 41 98 03 46' rather
%% than `98 03 46 20 00 41' three bytes later.
slide(Ops) ->
    compact(slide(Ops, [])).

slide([{eq, E}, {Op, X} | Rest], Acc) when Op =/= eq, E =/= <<>> ->
    case Rest of
        [{eq, _} | _] -> shift(E, Op, X, Rest, Acc);
        [] -> shift(E, Op, X, Rest, Acc);
        _ -> slide([{Op, X} | Rest], [{eq, E} | Acc])
    end;
slide([Op | Rest], Acc) ->
    slide(Rest, [Op | Acc]);
slide([], Acc) ->
    lists:reverse(Acc).

shift(E, Op, X, Rest, Acc) ->
    ELen = byte_size(E) - 1,
    XLen = byte_size(X) - 1,
    case {E, X} of
        {<<E1:ELen/binary, B>>, <<X1:XLen/binary, B>>} ->
            shift(E1, Op, <<B, X1/binary>>, prepend(B, Rest), Acc);
        _ ->
            slide(Rest, [{Op, X}, {eq, E} | Acc])
    end.

prepend(B, [{eq, N} | Rest]) -> [{eq, <<B, N/binary>>} | Rest];
prepend(B, []) -> [{eq, <<B>>}].

compact(Ops) ->
    compact([Op || {_, Bin} = Op <- Ops, Bin =/= <<>>], []).

compact([], Acc) ->
    lists:reverse(Acc);
compact([{Op, X} | Rest], [{Op, Y} | Acc]) ->
    compact(Rest, [{Op, <<Y/binary, X/binary>>} | Acc]);
compact([Op | Rest], Acc) ->
    compact(Rest, [Op | Acc]).

%% Myers, "An O(ND) Difference Algorithm and Its Variations" (1986): the
%% forward search keeps, for each edit distance D, the furthest point reached
%% on every diagonal K; the path is then read back from those snapshots.
myers(A, B) ->
    N = byte_size(A),
    M = byte_size(B),
    case search(A, B, N, M, 0, #{1 => 0}, []) of
        {ok, Trace} -> {ok, backtrack(A, B, N, M, Trace)};
        too_many -> too_many
    end.

search(_A, _B, _N, _M, D, _V, _Trace) when D > ?MAX_EDITS ->
    too_many;
search(A, B, N, M, D, V, Trace) ->
    case diagonals(A, B, N, M, D, -D, V) of
        {done, _V1} -> {ok, [V | Trace]};
        {more, V1} -> search(A, B, N, M, D + 1, V1, [V | Trace])
    end.

diagonals(_A, _B, _N, _M, D, K, V) when K > D ->
    {more, V};
diagonals(A, B, N, M, D, K, V) ->
    X0 = case K =:= -D orelse (K =/= D andalso maps:get(K - 1, V) < maps:get(K + 1, V)) of
             true -> maps:get(K + 1, V);
             false -> maps:get(K - 1, V) + 1
         end,
    X = snake(A, B, N, M, X0, X0 - K),
    V1 = V#{K => X},
    case X >= N andalso X - K >= M of
        true -> {done, V1};
        false -> diagonals(A, B, N, M, D, K + 2, V1)
    end.

snake(A, B, N, M, X, Y) when X < N, Y < M ->
    case binary:at(A, X) =:= binary:at(B, Y) of
        true -> snake(A, B, N, M, X + 1, Y + 1);
        false -> X
    end;
snake(_A, _B, _N, _M, X, _Y) ->
    X.

%% `Trace' is newest first: the snapshot taken before step D is at the head
%% when D is the last step.
backtrack(A, B, N, M, Trace) ->
    back(A, B, N, M, length(Trace) - 1, Trace, []).

back(_A, _B, _X, _Y, _D, [], Acc) ->
    Acc;
back(A, B, X, Y, D, [V | Trace], Acc) ->
    K = X - Y,
    PrevK = case K =:= -D orelse (K =/= D andalso maps:get(K - 1, V) < maps:get(K + 1, V)) of
                true -> K + 1;
                false -> K - 1
            end,
    PrevX = maps:get(PrevK, V),
    PrevY = PrevX - PrevK,
    {X1, _Y1, Acc1} = diagonal(A, X, Y, PrevX, PrevY, Acc),
    Acc2 = if
               D =:= 0 -> Acc1;
               X1 =:= PrevX -> [{ins, binary:part(B, PrevY, 1)} | Acc1];
               true -> [{del, binary:part(A, PrevX, 1)} | Acc1]
           end,
    back(A, B, PrevX, PrevY, D - 1, Trace, Acc2).

diagonal(A, X, Y, PrevX, PrevY, Acc) when X > PrevX, Y > PrevY ->
    diagonal(A, X - 1, Y - 1, PrevX, PrevY, [{eq, binary:part(A, X - 1, 1)} | Acc]);
diagonal(_A, X, Y, _PrevX, _PrevY, Acc) ->
    {X, Y, Acc}.
