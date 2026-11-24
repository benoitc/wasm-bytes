%% Writes the term files a track's preparation produces: `case.config' and
%% `selection.config', read back with `file:consult/1'.
%%
%% `io_lib:format("~p")' prints a list of small integers as a string, so the
%% arguments `[65, 66]' would come out as "AB" and the line numbers
%% `[181, 182]' as Latin-1 text that is not UTF-8. Here a list is always a
%% list, text is always a binary, and a long list puts one element per line.
-module(wb_terms).

-export([write/3, format/1]).

-spec write(file:filename(), iodata(), [{atom(), term()}]) -> ok.
write(Path, Comment, Terms) ->
    ok = filelib:ensure_dir(Path),
    Lines = [["%% ", L, "\n"] || L <- string:split(iolist_to_binary(Comment), "\n", all)],
    ok = file:write_file(Path, unicode:characters_to_binary(
                                 [Lines | [[format(T), ".\n"] || T <- Terms]])).

%% One top-level term. A list of more than three items, or of compound
%% items, is written one item per line.
-spec format(term()) -> iodata().
format({Key, List}) when is_list(List), length(List) > 3;
                         is_list(List), List =/= [], is_tuple(hd(List)) ->
    ["{", atom_to_list(Key), ", [\n",
     lists:join(",\n", [["    ", term(E)] || E <- List]),
     "]}"];
format(T) ->
    term(T).

term(B) when is_binary(B) ->
    case unicode:characters_to_list(B) of
        L when is_list(L) ->
            case lists:all(fun(C) -> C < 128 end, L) of
                true -> ["<<\"", escape(L), "\">>"];
                false -> ["<<\"", escape(L), "\"/utf8>>"]
            end;
        _ -> io_lib:format("~w", [B])
    end;
term(L) when is_list(L) ->
    ["[", lists:join(", ", [term(E) || E <- L]), "]"];
term(T) when is_tuple(T) ->
    ["{", lists:join(", ", [term(E) || E <- tuple_to_list(T)]), "}"];
term(X) ->
    io_lib:format("~w", [X]).

escape(Chars) ->
    [case C of
         $" -> "\\\"";
         $\\ -> "\\\\";
         $\n -> "\\n";
         $\t -> "\\t";
         _ when C < 32 -> io_lib:format("\\x{~.16b}", [C]);
         _ -> C
     end || C <- Chars].
