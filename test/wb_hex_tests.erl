-module(wb_hex_tests).

-include_lib("eunit/include/eunit.hrl").

decodes_pairs_test() ->
    ?assertEqual({ok, <<0, 16#61, 16#73, 16#6d>>}, wb_hex:decode(~"00 61 73 6d")),
    ?assertEqual({ok, <<0, 16#61, 16#73, 16#6d>>}, wb_hex:decode(~"0061736d")),
    ?assertEqual({ok, <<16#ab, 16#cd>>}, wb_hex:decode(~"AB cd")).

whitespace_between_pairs_test() ->
    ?assertEqual({ok, <<1, 2, 3, 4>>}, wb_hex:decode(~"\n 01\t02\r\n03\n\n04  \n")).

empty_test() ->
    ?assertEqual({error, empty}, wb_hex:decode(~"")),
    ?assertEqual({error, empty}, wb_hex:decode(~" \n\t")).

not_hex_reports_line_and_column_test() ->
    ?assertEqual({error, {not_hex, 1, 7, $x}}, wb_hex:decode(~"00 61 x")),
    ?assertEqual({error, {not_hex, 2, 2, $g}}, wb_hex:decode(~"00\n0g")),
    ?assertEqual({error, {not_hex, 1, 2, $x}}, wb_hex:decode(~"0x00")),
    ?assertEqual({error, {not_hex, 1, 1, $`}}, wb_hex:decode(~"```\n00\n```")).

column_counts_characters_test() ->
    ?assertEqual({error, {not_hex, 1, 4, 16#e9}}, wb_hex:decode(~"00 é")).

split_pair_is_refused_test() ->
    ?assertEqual({error, {unpaired_digit, 1, 1}}, wb_hex:decode(~"0 061")),
    ?assertEqual({error, {unpaired_digit, 1, 4}}, wb_hex:decode(~"00 6\n")).

odd_digit_count_is_refused_test() ->
    ?assertEqual({error, {unpaired_digit, 1, 3}}, wb_hex:decode(~"006")).

encode_round_trips_test() ->
    rand:seed(exsss, {1, 2, 3}),
    [begin
         Bin = rand:bytes(rand:uniform(100)),
         ?assertEqual({ok, Bin}, wb_hex:decode(iolist_to_binary(wb_hex:encode(Bin))))
     end || _ <- lists:seq(1, 200)].

encode_writes_sixteen_pairs_a_line_test() ->
    Lines = string:split(iolist_to_binary(wb_hex:encode(list_to_binary(lists:seq(0, 33)))),
                         "\n", all),
    ?assertEqual([16, 16, 2], [length(string:split(L, " ", all)) || L <- Lines, L =/= <<>>]).
