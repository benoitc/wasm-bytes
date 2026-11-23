-module(wb_layout_tests).

-include_lib("eunit/include/eunit.hrl").

sonnet() ->
    {ok, Text} = file:read_file(filename:join(wb_test_io:root(),
                                              "trials/write/claude-sonnet-5-5-1/reply.txt")),
    {ok, Bytes} = wb_hex:decode(Text),
    Bytes.

sections_test() ->
    {ok, Sections} = wb_layout:sections(sonnet()),
    ?assertEqual([{1, 8, 6}, {3, 16, 2}, {7, 20, 9}, {10, 31, 21}],
                 [{Id, At, Size} || #{id := Id, at := At, size := Size} <- Sections]).

not_a_module_test() ->
    ?assertEqual({error, 0}, wb_layout:sections(~"not wasm")).

%% A section that says it is longer than what follows stops the walk at that
%% section's id byte.
truncated_section_test() ->
    ?assertEqual({error, 8}, wb_layout:sections(<<0, "asm", 1, 0, 0, 0, 1, 9, 1, 96>>)).

exports_test() ->
    Bytes = sonnet(),
    {ok, Sections} = wb_layout:sections(Bytes),
    [Export] = wb_layout:find(7, Sections),
    ?assertEqual([{~"retry", func, 0}], wb_layout:exports(Bytes, Export)),
    [Funcs] = wb_layout:find(3, Sections),
    ?assertEqual(1, wb_layout:count(Bytes, Funcs)).

describe_test() ->
    Bytes = sonnet(),
    Cases = [{0, ~"magic number"}, {5, ~"version"},
             {8, ~"type section id"}, {9, ~"type section length"}, {10, ~"type section"},
             {20, ~"export section id"}, {22, ~"export section"},
             {31, ~"code section id"}, {32, ~"code section length"},
             {33, ~"code section entry count"}, {34, ~"length of function body 0"},
             {35, ~"function body 0"}, {53, ~"function body 0"},
             {54, ~"end of module"}],
    [?assertEqual({At, Want}, {At, iolist_to_binary(wb_layout:describe(Bytes, At))})
     || {At, Want} <- Cases].

describe_broken_module_test() ->
    ?assertEqual(~"a module that does not decode",
                 iolist_to_binary(wb_layout:describe(<<0, "asm", 1, 0, 0, 0, 1, 9>>, 8))).

section_names_test() ->
    Names = [iolist_to_binary(wb_layout:section_name(Id)) || Id <- lists:seq(0, 13)],
    ?assertEqual(length(Names), length(lists:usort(Names))),
    ?assertEqual(~"unknown (99)", iolist_to_binary(wb_layout:section_name(99))).
