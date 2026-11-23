%% Follows one recorded trial from the prompt the model received to the module
%% that runs: the prompt as sent, the reply as received, the bytes decoded
%% from it section by section, and their SHA-256.
%%
%% `module.sha256' in the trial directory, in `shasum -a 256' format, is the
%% hash recorded for those bytes. Every engine and platform that runs the
%% module can be checked against it.
-module(wb_trace).

-export([load/1, trace/1, recorded_sha256/1, sha256/1]).

-spec load(file:filename()) -> {ok, map()} | {error, term()}.
load(Dir) ->
    case {file:read_file(filename:join(Dir, "prompt.txt")),
          file:read_file(filename:join(Dir, "reply.txt"))} of
        {{ok, Prompt}, {ok, Reply}} ->
            Config = case file:consult(filename:join(Dir, "fixture.config")) of
                         {ok, Terms} -> maps:from_list(Terms);
                         {error, _} -> #{}
                     end,
            {ok, #{dir => Dir, prompt => Prompt, reply => Reply, config => Config,
                   decoded => wb_hex:decode(Reply),
                   recorded => recorded_sha256(Dir)}};
        {{error, Why}, _} ->
            {error, {filename:join(Dir, "prompt.txt"), Why}};
        {_, {error, Why}} ->
            {error, {filename:join(Dir, "reply.txt"), Why}}
    end.

-spec recorded_sha256(file:filename()) -> binary() | missing.
recorded_sha256(Dir) ->
    case file:read_file(filename:join(Dir, "module.sha256")) of
        {ok, Line} -> hd(string:split(string:trim(Line), " "));
        {error, enoent} -> missing
    end.

-spec sha256(binary()) -> binary().
sha256(Bytes) ->
    binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

-spec trace(map()) -> iodata().
trace(#{dir := Dir, prompt := Prompt, reply := Reply, config := C} = T) ->
    [heading(["Trial ", Dir]),
     case C of
         #{model := Model, recorded_on := On, interface := Iface} ->
             [field("model", Model), field("recorded", On), field("interface", Iface)];
         _ -> field("model", "not recorded: this is not a model trial")
     end,
     $\n,
     heading(io_lib:format("Prompt: prompt.txt, ~b bytes, sent to the model exactly as below",
                           [byte_size(Prompt)])),
     quoted(Prompt),
     $\n,
     heading(io_lib:format("Reply: reply.txt, ~b bytes, as the model returned it",
                           [byte_size(Reply)])),
     quoted(Reply),
     $\n,
     module(T)].

module(#{decoded := {error, Why}}) ->
    [heading("Module"), field("hex", io_lib:format("the reply is not hex: ~0p", [Why]))];
module(#{decoded := {ok, Bytes}, recorded := Recorded}) ->
    Hash = sha256(Bytes),
    [heading(io_lib:format("Module: the ~b bytes the hex decodes to, nothing added or changed",
                           [byte_size(Bytes)])),
     layout(Bytes),
     $\n,
     field("size", io_lib:format("~b bytes", [byte_size(Bytes)])),
     field("sha256", Hash),
     field("recorded", case Recorded of
                           missing -> "no module.sha256 in the trial directory";
                           Hash -> "module.sha256 holds the same hash";
                           Other -> ["module.sha256 holds a DIFFERENT hash: ", Other]
                       end)].

%% One row per piece of the module: the header, then each section's id and
%% length, then its contents, sixteen bytes to a row.
layout(Bytes) ->
    case wb_layout:sections(Bytes) of
        {ok, Sections} ->
            [row(0, binary:part(Bytes, 0, 4), "magic number: \\0asm"),
             row(4, binary:part(Bytes, 4, 4), "version 1"),
             [section(Bytes, S) || S <- Sections]];
        {error, At} ->
            [row(0, Bytes, io_lib:format("does not decode as sections past offset ~b", [At]))]
    end.

section(Bytes, #{id := Id, at := At, payload := P, size := Size}) ->
    [row(At, binary:part(Bytes, At, P - At),
         io_lib:format("~ts section, ~b bytes follow", [wb_layout:section_name(Id), Size])),
     row(P, binary:part(Bytes, P, Size), contents(Id))].

contents(1) -> "  function types";
contents(3) -> "  which type each function has";
contents(7) -> "  exports: name, kind, index";
contents(10) -> "  function bodies: the instructions";
contents(_) -> "".

row(_At, <<>>, _Text) ->
    [];
row(At, Bin, Text) ->
    Lines = [L || L <- string:split(iolist_to_binary(wb_hex:encode(Bin)), "\n", all), L =/= <<>>],
    [First | Rest] = Lines,
    [string:trim(io_lib:format("  0x~4.16.0b  ~-48ts ~ts", [At, First, Text]), trailing), $\n,
     [["          ", L, $\n] || L <- Rest]].

heading(Text) ->
    [Text, $\n].

field(Tag, Text) ->
    [io_lib:format("  ~-10s ", [Tag]), Text, $\n].

quoted(Text) ->
    Lines = string:split(Text, "\n", all),
    %% A final newline ends the last line; it does not start another.
    Shown = case lists:last(Lines) of
                <<>> -> lists:droplast(Lines);
                _ -> Lines
            end,
    [["  | ", L, $\n] || L <- Shown].
