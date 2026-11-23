%% Builds the audible DX-Ball pan demo: a page in `_build/pan-demo/' that
%% runs two recorded modules, the original pan and its reversed revision.
%%
%% Both replies are checked again first: the original must pass the `pan'
%% task, and the reversed one must pass `reverse' with the original as its
%% base. The page then receives the exact bytes each reply decodes to, with
%% their SHA-256, and the host page in `demo/pan/' runs them.
-module(wb_pan_demo).

-export([build/4, default_replies/0]).

-define(ORIGINAL, "trials/pan/claude-sonnet-5-5-1/reply.txt").
-define(REVERSED, "trials/reverse/claude-sonnet-5-5-1/reply.txt").

-spec default_replies() -> {string(), string()}.
default_replies() ->
    {?ORIGINAL, ?REVERSED}.

%% `{ok, IndexHtml}' or `{error, Why}' with the report that refused a reply.
-spec build(file:filename(), file:filename(), file:filename(), file:filename()) ->
          {ok, file:filename()} | {error, term()}.
build(Root, OriginalReply, ReversedReply, OutDir) ->
    {ok, OText} = file:read_file(OriginalReply),
    {ok, RText} = file:read_file(ReversedReply),
    case wb_check:check_revision(reverse, OText, RText) of
        {error, {base_not_accepted, Report}} ->
            {error, {original_refused, Report}};
        {ok, #{base := #{bytes := OBytes}, revised := #{verdict := pass, bytes := RBytes}}} ->
            ok = filelib:ensure_path(OutDir),
            [{ok, _} = file:copy(filename:join([Root, "demo", "pan", F]), filename:join(OutDir, F))
             || F <- ["index.html", "app.js"]],
            Modules = #{original => entry("Original", Root, OriginalReply, OBytes),
                        reversed => entry("Reversed", Root, ReversedReply, RBytes)},
            ok = file:write_file(filename:join(OutDir, "modules.js"),
                                 ["// Written by bin/wasm-bytes pan-demo from the recorded replies.\n"
                                  "window.PAN_MODULES = ", json:encode(Modules), ";\n"]),
            {ok, filename:join(OutDir, "index.html")};
        {ok, #{revised := Revised}} ->
            {error, {reversed_refused, Revised}}
    end.

entry(Label, Root, Reply, Bytes) ->
    #{label => list_to_binary(Label),
      reply => relative(Root, Reply),
      model => model(filename:dirname(Reply)),
      sha256 => wb_trace:sha256(Bytes),
      bytes => base64:encode(Bytes)}.

%% Who wrote the reply, from the fixture beside it.
model(Dir) ->
    case file:consult(filename:join(Dir, "fixture.config")) of
        {ok, Terms} ->
            case proplists:get_value(source, Terms) of
                model_trial -> unicode:characters_to_binary(proplists:get_value(model, Terms, "?"));
                _ -> ~"a constructed example, not a model trial"
            end;
        {error, _} ->
            ~"not recorded"
    end.

relative(Root, Path) ->
    Abs = filename:absname(Path),
    Prefix = filename:absname(Root) ++ "/",
    unicode:characters_to_binary(case lists:prefix(Prefix, Abs) of
                                     true -> lists:nthtail(length(Prefix), Abs);
                                     false -> Path
                                 end).
