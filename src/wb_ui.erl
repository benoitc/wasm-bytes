%% Checks a generated demo page: the `ui' task.
%%
%% The reply must be an HTML document. It is then opened twice in headless
%% Chrome by `scripts/ui-check.mjs': once with the recorded DX-Ball pan
%% modules, once with stand-in modules that always return 250 and -125, so a
%% page that computes the pan itself is caught. Node and Chrome are optional:
%% without them the check says what is missing, as `compare' does without
%% Wasmtime.
-module(wb_ui).

-export([check/2, check/3, tools/0, report/1]).

-export_type([report/0]).

-type report() :: #{task := ui, verdict := pass | not_html | ui_failed | runner_error,
                    text_bytes := non_neg_integer(), atom() => term()}.

%% The stand-in modules: screen_pan returns 250, and -125, whatever x is.
-define(PROBE_ORIGINAL, "0061736d0100000001060160017f017f03020100070e010a73637265656e5f70616e00000a0701050041fa010b").
-define(PROBE_REVERSED, "0061736d0100000001060160017f017f03020100070e010a73637265656e5f70616e00000a0701050041837f0b").
-define(TIMEOUT_MS, 120_000).

%% With the recorded Sonnet pair, as the demo page uses.
-spec check(file:filename(), binary()) -> {ok, report()} | {error, {missing, node | chrome} | term()}.
check(Root, Text) ->
    {Original, Reversed} = wb_pan_demo:default_replies(),
    check(Root, Text, {filename:join(Root, Original), filename:join(Root, Reversed)}).

-spec check(file:filename(), binary(), {file:filename(), file:filename()}) ->
          {ok, report()} | {error, {missing, node | chrome} | term()}.
check(Root, Text, {Original, Reversed}) ->
    R = #{task => ui, text_bytes => byte_size(Text)},
    case is_html(Text) of
        false ->
            {ok, R#{verdict => not_html, why => first_line(Text)}};
        true ->
            case {tools(), wb_pan_demo:modules_js(Root, Original, Reversed)} of
                {{error, Missing}, _} -> {error, {missing, Missing}};
                {_, {error, Why}} -> {error, Why};
                {{ok, Node, Chrome}, {ok, Js}} -> {ok, run(Root, Text, Js, Node, Chrome, R)}
            end
    end.

%% Node and a Chrome or Chromium. NODE and CHROME name them when they are
%% not where they usually are.
-spec tools() -> {ok, file:filename(), file:filename()} | {error, node | chrome}.
tools() ->
    Node = case os:getenv("NODE") of
               P when is_list(P), P =/= "" -> P;
               _ -> os:find_executable("node")
           end,
    Chrome = case os:getenv("CHROME") of
                 P2 when is_list(P2), P2 =/= "" -> P2;
                 _ -> first_chrome()
             end,
    if
        Node =:= false -> {error, node};
        Chrome =:= false -> {error, chrome};
        true -> {ok, Node, Chrome}
    end.

first_chrome() ->
    Mac = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    case filelib:is_regular(Mac) of
        true -> Mac;
        false ->
            case [E || E <- [os:find_executable(N) || N <- ["google-chrome", "google-chrome-stable",
                                                             "chromium", "chromium-browser"]],
                       E =/= false] of
                [E | _] -> E;
                [] -> false
            end
    end.

is_html(Text) ->
    Start = string:trim(Text, leading, [$\s, $\t, $\r, $\n, 16#FEFF]),
    string:prefix(string:lowercase(Start), "<!doctype html") =/= nomatch.

first_line(Text) ->
    [Line | _] = string:split(string:trim(Text, leading), "\n"),
    string:slice(string:trim(Line), 0, 60).

run(Root, Text, Js, Node, Chrome, R) ->
    Dir = temp_dir(),
    try
        write_page(filename:join(Dir, "real"), Text, Js),
        write_page(filename:join(Dir, "probe"), Text, probe_js()),
        Script = filename:join([Root, "scripts", "ui-check.mjs"]),
        case exec(Node, [Script, "--chrome", Chrome, "--dir", Dir]) of
            {ok, Out} -> result(Out, R);
            {error, Why} -> R#{verdict => runner_error, why => Why}
        end
    after
        file:del_dir_r(Dir)
    end.

write_page(Dir, Text, Js) ->
    ok = filelib:ensure_path(Dir),
    ok = file:write_file(filename:join(Dir, "index.html"), Text),
    ok = file:write_file(filename:join(Dir, "modules.js"), Js).

probe_js() ->
    Entry = fun(Label, Hex, Value) ->
                Bytes = binary:decode_hex(list_to_binary(Hex)),
                #{label => Label, reply => ~"none",
                  model => iolist_to_binary(["a stand-in module that always returns ", Value]),
                  sha256 => wb_trace:sha256(Bytes), bytes => base64:encode(Bytes)}
            end,
    ["window.PAN_MODULES = ",
     json:encode(#{original => Entry(~"Original", ?PROBE_ORIGINAL, "250"),
                   reversed => Entry(~"Reversed", ?PROBE_REVERSED, "-125")}),
     ";\n"].

result(Out, R) ->
    case decode(string:trim(Out)) of
        #{<<"checks">> := Checks} = J ->
            List = [{binary_to_atom(N), Ok, D}
                    || #{<<"name">> := N, <<"ok">> := Ok, <<"detail">> := D} <- Checks],
            R#{verdict => case lists:all(fun({_, Ok, _}) -> Ok end, List) of
                              true -> pass;
                              false -> ui_failed
                          end,
               checks => List, browser => maps:get(<<"chrome">>, J, ~"?")};
        #{<<"error">> := Why} ->
            R#{verdict => runner_error, why => Why};
        _ ->
            R#{verdict => runner_error, why => string:slice(Out, 0, 400)}
    end.

decode(Text) ->
    try json:decode(Text)
    catch error:_ -> undefined
    end.

exec(Exe, Args) ->
    Port = open_port({spawn_executable, Exe}, [{args, Args}, exit_status, binary, hide]),
    collect(Port, []).

collect(Port, Acc) ->
    receive
        {Port, {data, D}} -> collect(Port, [D | Acc]);
        {Port, {exit_status, 0}} -> {ok, iolist_to_binary(lists:reverse(Acc))};
        {Port, {exit_status, _}} -> {ok, iolist_to_binary(lists:reverse(Acc))}
    after ?TIMEOUT_MS ->
        try port_close(Port) catch error:badarg -> ok end,
        {error, ~"the browser check did not finish in two minutes"}
    end.

temp_dir() ->
    Base = case os:getenv("TMPDIR") of
               T when is_list(T), T =/= "" -> T;
               _ -> "/tmp"
           end,
    Dir = filename:join(Base, "wasm-bytes-ui-" ++ integer_to_list(erlang:unique_integer([positive]))
                              ++ "-" ++ os:getpid()),
    ok = file:make_dir(Dir),
    Dir.

-spec report(report()) -> iodata().
report(#{verdict := not_html, why := Line, text_bytes := N}) ->
    [line("html", io_lib:format("not an HTML document: the ~b-byte reply starts with \"~ts\"", [N, Line])),
     line("verdict", "not_html")];
report(#{verdict := runner_error, why := Why}) ->
    [line("runner", io_lib:format("~ts", [Why])), line("verdict", "runner_error")];
report(#{checks := Checks, browser := Browser, text_bytes := N, verdict := V}) ->
    [line("html", io_lib:format("an HTML document of ~b bytes", [N])),
     line("browser", [Browser, ", headless; the recorded modules, then stand-ins returning 250 and -125"]),
     [line("check", io_lib:format("~-4s ~ts: ~ts", [case Ok of true -> "ok"; false -> "FAIL" end, Name, D]))
      || {Name, Ok, D} <- Checks],
     line("verdict", atom_to_list(V))].

line(Tag, Text) ->
    [io_lib:format("  ~-8s ", [Tag]), Text, $\n].
