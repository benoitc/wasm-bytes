%% Strict hex decoding of a model reply.
%%
%% A reply is hex digit pairs, with optional whitespace (space, tab, CR, LF)
%% between pairs. Anything else is refused with the line and column of the
%% first problem. The decoder never guesses: a code fence, a `0x' prefix, a
%% comment or a pair split by whitespace is malformed hex, not something to
%% clean up.
-module(wb_hex).

-export([decode/1, encode/1]).

-export_type([error/0]).

-type error() :: empty
               | {not_hex, Line :: pos_integer(), Col :: pos_integer(), char()}
               | {unpaired_digit, Line :: pos_integer(), Col :: pos_integer()}.

-spec decode(binary()) -> {ok, binary()} | {error, error()}.
decode(Text) when is_binary(Text) ->
    scan(chars(Text), 1, 1, none, []).

%% Columns count characters, so a reply in UTF-8 reports the column a person
%% sees. Bytes that are not UTF-8 are read one per column.
chars(Text) ->
    case unicode:characters_to_list(Text) of
        L when is_list(L) -> L;
        _ -> binary_to_list(Text)
    end.

scan([], _Line, _Col, none, []) ->
    {error, empty};
scan([], _Line, _Col, none, Acc) ->
    {ok, list_to_binary(lists:reverse(Acc))};
scan([], _Line, _Col, {_Hi, L, C}, _Acc) ->
    {error, {unpaired_digit, L, C}};
scan([$\n | Rest], Line, Col, Pending, Acc) ->
    between_pairs(Pending, fun() -> scan(Rest, Line + 1, 1, none, Acc) end, Line, Col);
scan([Ws | Rest], Line, Col, Pending, Acc) when Ws =:= $\s; Ws =:= $\t; Ws =:= $\r ->
    between_pairs(Pending, fun() -> scan(Rest, Line, Col + 1, none, Acc) end, Line, Col);
scan([Ch | Rest], Line, Col, Pending, Acc) ->
    case nibble(Ch) of
        error ->
            {error, {not_hex, Line, Col, Ch}};
        N ->
            case Pending of
                none -> scan(Rest, Line, Col + 1, {N, Line, Col}, Acc);
                {Hi, _, _} -> scan(Rest, Line, Col + 1, none, [Hi * 16 + N | Acc])
            end
    end.

%% Whitespace is allowed between pairs only.
between_pairs(none, Continue, _Line, _Col) -> Continue();
between_pairs({_Hi, L, C}, _Continue, _Line, _Col) -> {error, {unpaired_digit, L, C}}.

nibble(C) when C >= $0, C =< $9 -> C - $0;
nibble(C) when C >= $a, C =< $f -> C - $a + 10;
nibble(C) when C >= $A, C =< $F -> C - $A + 10;
nibble(_) -> error.

%% Lowercase pairs, sixteen to a line: how the revise prompt shows the bytes.
-spec encode(binary()) -> iodata().
encode(Bytes) ->
    lines(Bytes).

lines(<<>>) ->
    [];
lines(<<Line:16/binary, Rest/binary>>) when Rest =/= <<>> ->
    [pairs(Line), $\n | lines(Rest)];
lines(Line) ->
    [pairs(Line), $\n].

pairs(Bin) ->
    lists:join($\s, [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).
