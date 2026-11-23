%% Turns check reports into the lines the runner prints.
-module(wb_report).

-export([report/1, revision/2, base_refused/2, outcome/1]).

%% Every stage the reply reached, then its verdict.
-spec report(wb_check:report()) -> iodata().
report(R) ->
    [stages(R), verdict(R)].

%% `BaseName' says where the base came from: a fixture or a file.
-spec revision(iodata(), wb_check:revision()) -> iodata().
revision(BaseName, #{base := Base, revised := Revised} = Rev) ->
    [line("base", io_lib:format("~ts: ~b bytes, passes task 1",
                                [BaseName, byte_size(maps:get(bytes, Base))])),
     stages(Revised),
     diff(Rev),
     changes(Rev),
     verdict(Revised)].

-spec base_refused(binary(), wb_check:report()) -> iodata().
base_refused(Name, Base) ->
    [line("base", [Name, " does not pass task 1, so it cannot be the base of a revision"]),
     report(Base)].

stages(R) ->
    [text_size(R), hex(R), wasm(R), profile(R), calls(R)].

text_size(#{verdict := too_large, why := {text, N, Max}}) ->
    line("size", io_lib:format("~b bytes of reply; the limit is ~b", [N, Max]));
text_size(_) ->
    [].

hex(#{verdict := malformed_hex, why := Why}) ->
    line("hex", ["malformed: ", hex_error(Why)]);
hex(#{verdict := too_large, why := {bytes, N, Max}}) ->
    line("hex", io_lib:format("~b bytes; the limit is ~b", [N, Max]));
hex(#{bytes := Bytes}) ->
    line("hex", io_lib:format("~b bytes", [byte_size(Bytes)]));
hex(_) ->
    [].

hex_error(empty) ->
    "no hex digits";
hex_error({not_hex, L, C, Ch}) ->
    io_lib:format("line ~b, column ~b: ~ts is not a hex digit or whitespace",
                  [L, C, show_char(Ch)]);
hex_error({unpaired_digit, L, C}) ->
    io_lib:format("line ~b, column ~b: a hex digit without its pair", [L, C]).

show_char($`) -> "a backtick";
show_char(Ch) when Ch > 32, Ch < 127 -> [$', Ch, $'];
show_char(Ch) -> io_lib:format("U+~4.16.0B", [Ch]).

wasm(#{verdict := V, why := E}) when V =:= malformed_wasm; V =:= invalid ->
    line("wasm", wasm_error(E));
wasm(#{verdict := runner_error, why := Why}) ->
    line("runner", io_lib:format("~0P", [Why, 20]));
wasm(#{bytes := _} = R) when not is_map_key(why, R); map_get(verdict, R) =:= interface_mismatch ->
    line("wasm", ["decodes and validates (erlang_wasm ", wasm_version(), ")"]);
wasm(_) ->
    [].

%% The error map's fields, with the whole context: `wasm:format_error/1' keeps
%% only some keys, and for a malformed module the ones it drops (the declared
%% size, the bytes remaining, the section) are the ones that say what is wrong.
wasm_error(#{class := Class, kind := Kind, msg := Msg} = E) ->
    [atom_to_list(Class), ": ", Msg, " (", atom_to_list(Kind), ")",
     case maps:get(ctx, E, #{}) of
         Ctx when map_size(Ctx) > 0 -> io_lib:format(" ~0p", [Ctx]);
         _ -> []
     end];
wasm_error(E) ->
    io_lib:format("~0P", [E, 12]).

profile(#{verdict := interface_mismatch, why := Violations}) ->
    [line("profile", wb_profile:format_violation(V)) || V <- Violations];
profile(#{task := Task, results := _}) ->
    #{export := Export, params := P, results := Rs} = wb_task:get(Task),
    line("profile", ["one function, exported as ", Export, " : ",
                     wb_profile:signature({P, Rs}), "; no imports, memory or start"]);
profile(_) ->
    [].

calls(#{results := Results, failures := Failures, wrong := Wrong}) ->
    #{fuel := Fuel, deadline_ms := Deadline} = wb_exec:limits(),
    Total = length(wb_task:inputs()),
    Matched = length(Results) - length(Failures) - length(Wrong),
    [line("calls", io_lib:format("~b inputs, each in a fresh instance; fuel ~b and a ~b ms "
                                 "deadline per call", [Total, Fuel, Deadline])),
     case Failures of
         [] -> [];
         [{instantiate, Why}] -> line("failed", ["instantiation failed: ", error_text(Why)]);
         _ -> [line("failed", io_lib:format("~b call~s did not return a result",
                                            [length(Failures), plural(Failures)])),
               grouped([{X, failure_text(E)} || {X, E} <- Failures])]
     end,
     case Wrong of
         [] -> [];
         _ -> [line("wrong", case Wrong of
                                 [_] -> "1 answer differs from the reference";
                                 _ -> io_lib:format("~b answers differ from the reference",
                                                    [length(Wrong)])
                             end),
               grouped([{X, io_lib:format("expected ~b, got ~b", [Want, Got])}
                        || {X, Want, Got} <- Wrong])]
     end,
     line("answers", io_lib:format("~b of ~b match the reference", [Matched, Total]))];
calls(_) ->
    [].

failure_text(not_run) -> "not run, after too many deadlines";
failure_text(E) -> error_text(E).

%% One line per outcome, naming every input that had it: `input 599: expected
%% 1, got 0' for one input, and for several the outcome, how many, and the
%% inputs, with each run of three or more consecutive integers as `A to B'.
grouped(Items) ->
    Keys = lists:usort([iolist_to_binary(K) || {_, K} <- Items]),
    Groups = [{K, lists:sort([X || {X, K1} <- Items, iolist_to_binary(K1) =:= K])} || K <- Keys],
    [case Xs of
         [X] -> line("", [io_lib:format("input ~b: ", [X]), K]);
         _ -> [line("", [K, io_lib:format(" on ~b inputs:", [length(Xs)])]),
               [line("", ["  ", L]) || L <- wrap(segments(Xs))]]
     end || {K, Xs} <- lists:sort(fun({_, [A | _]}, {_, [B | _]}) -> A =< B end, Groups)].

segments([]) ->
    [];
segments([X | Rest]) ->
    {Run, Tail} = run(X, Rest),
    Last = lists:last([X | Run]),
    Seg = case length(Run) of
              0 -> [integer_to_list(X)];
              1 -> [integer_to_list(X), integer_to_list(Last)];
              _ -> [io_lib:format("~b to ~b", [X, Last])]
          end,
    Seg ++ segments(Tail).

run(Prev, [X | Rest]) when X =:= Prev + 1 ->
    {Run, Tail} = run(X, Rest),
    {[X | Run], Tail};
run(_Prev, Rest) ->
    {[], Rest}.

%% Comma-separated, about 64 characters a line.
wrap(Segs) ->
    wrap(Segs, [], []).

wrap([], [], Lines) ->
    lists:reverse(Lines);
wrap([], Cur, Lines) ->
    lists:reverse([lists:join(", ", lists:reverse(Cur)) | Lines]);
wrap([S | Rest], Cur, Lines) ->
    Len = iolist_size(lists:join(", ", lists:reverse([S | Cur]))),
    case Cur =/= [] andalso Len > 64 of
        true -> wrap([S | Rest], [], [[lists:join(", ", lists:reverse(Cur)), ","] | Lines]);
        false -> wrap(Rest, [S | Cur], Lines)
    end.

error_text(#{class := Class, kind := Kind} = E) ->
    [atom_to_list(Class), "/", atom_to_list(Kind),
     case E of
         #{msg := Msg} -> [": ", Msg];
         _ -> []
     end];
error_text(Other) ->
    io_lib:format("~0P", [Other, 12]).

diff(#{hunks := Hunks, base := #{bytes := A}, revised := #{bytes := B}}) ->
    [line("diff", io_lib:format("~b -> ~b bytes, ~b hunk~s",
                                [byte_size(A), byte_size(B), length(Hunks),
                                 case length(Hunks) of 1 -> ""; _ -> "s" end])),
     [hunk(A, H) || H <- Hunks]];
diff(_) ->
    line("diff", "none: the revision is not hex").

hunk(A, #{base_at := AAt, base := Del, revised_at := BAt, revised := Ins}) ->
    [line("", io_lib:format("@ base 0x~4.16.0b, revised 0x~4.16.0b: ~ts",
                            [AAt, BAt, wb_layout:describe(A, AAt)])),
     bytes_lines("  - ", Del),
     bytes_lines("  + ", Ins)].

bytes_lines(_Mark, <<>>) ->
    [];
bytes_lines(Mark, Bin) ->
    [line("", [Mark, string:trim(L)]) || L <- string:split(iolist_to_binary(wb_hex:encode(Bin)), "\n", all), L =/= <<>>].

changes(#{changes := Changes, intended := Intended}) ->
    Total = length(wb_task:inputs()),
    Requested = [X || {X, _, _} <- Intended],
    [line("changes", io_lib:format("~b of ~b inputs changed result", [length(Changes), Total])),
     [line("", [io_lib:format("~b: ", [X]), outcome(B), " -> ", outcome(A),
                     case lists:member({X, B, A}, wanted(Intended)) of
                         true -> "  (requested)";
                         false -> "  (not requested)"
                     end])
      || {X, B, A} <- Changes],
     request(Changes, Intended, Requested)];
changes(_) ->
    line("changes", "not measured: the revision did not run").

wanted(Intended) ->
    [{X, {ok, B}, {ok, A}} || {X, B, A} <- Intended].

request(Changes, Intended, Requested) ->
    Missing = [{X, B, A} || {X, B, A} <- Intended,
                            not lists:member({X, {ok, B}, {ok, A}}, Changes)],
    Unrequested = [C || {X, _, _} = C <- Changes, not lists:member(X, Requested)],
    Done = [io_lib:format("~b ~b -> ~b", [X, B, A]) || {X, B, A} <- Intended],
    case {Missing, Unrequested} of
        {[], []} ->
            line("request", ["done: ", lists:join(", ", Done), "; no other result changed"]);
        _ ->
            [[line("request", io_lib:format("missing: ~b should go ~b -> ~b", [X, B, A]))
              || {X, B, A} <- Missing],
             [line("request", [io_lib:format("not requested: ~b changed ", [X]),
                               outcome(Bf), " -> ", outcome(Af)])
              || {X, Bf, Af} <- Unrequested]]
    end.

-spec outcome(wb_exec:outcome()) -> iodata().
outcome({ok, V}) -> integer_to_list(V);
outcome({error, #{class := C, kind := K}}) -> ["error ", atom_to_list(C), "/", atom_to_list(K)];
outcome({error, _}) -> "error";
outcome(not_run) -> "not run".

plural([_]) -> "";
plural(_) -> "s".

verdict(#{verdict := V}) ->
    line("verdict", atom_to_list(V)).

line(Tag, Text) ->
    [io_lib:format("  ~-8s ", [Tag]), Text, $\n].

wasm_version() ->
    case application:get_key(wasm, vsn) of
        {ok, V} -> V;
        undefined -> "unknown version"
    end.
