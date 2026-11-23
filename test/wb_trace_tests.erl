%% The trace of trials written out here: what it says when a part is missing
%% or does not match.
-module(wb_trace_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MODULE_HEX, ~"00 61 73 6d 01 00 00 00").

trial(Name, Files) ->
    Dir = wb_test_io:scratch(Name),
    [ok = file:write_file(filename:join(Dir, F), Body) || {F, Body} <- Files],
    Dir.

text(Dir) ->
    {ok, T} = wb_trace:load(Dir),
    iolist_to_binary(wb_trace:trace(T)).

has(Text, Part) ->
    binary:match(Text, Part) =/= nomatch.

missing_files_test() ->
    NoPrompt = trial("trace-no-prompt", [{"reply.txt", ?MODULE_HEX}]),
    ?assertMatch({error, {_, enoent}}, wb_trace:load(NoPrompt)),
    NoReply = trial("trace-no-reply", [{"prompt.txt", ~"p"}]),
    ?assertMatch({error, {_, enoent}}, wb_trace:load(NoReply)).

not_a_trial_test() ->
    Dir = trial("trace-no-config", [{"prompt.txt", ~"p"}, {"reply.txt", ?MODULE_HEX}]),
    Text = text(Dir),
    ?assert(has(Text, ~"not recorded: this is not a model trial")),
    ?assert(has(Text, ~"no module.sha256 in the trial directory")),
    ?assertEqual(missing, wb_trace:recorded_sha256(Dir)).

recorded_hash_differs_test() ->
    Dir = trial("trace-other-hash", [{"prompt.txt", ~"p"}, {"reply.txt", ?MODULE_HEX},
                                     {"module.sha256", ~"abc123  module.wasm\n"}]),
    ?assertEqual(~"abc123", wb_trace:recorded_sha256(Dir)),
    ?assert(has(text(Dir), ~"module.sha256 holds a DIFFERENT hash: abc123")).

not_hex_test() ->
    Dir = trial("trace-not-hex", [{"prompt.txt", ~"p"}, {"reply.txt", ~"Sure! 00 61"}]),
    ?assert(has(text(Dir), ~"the reply is not hex")).

%% A header with no sections is a module the layout can still show.
header_only_test() ->
    Dir = trial("trace-header", [{"prompt.txt", ~"line one\nline two\n"},
                                 {"reply.txt", ?MODULE_HEX}]),
    Text = text(Dir),
    ?assert(has(Text, ~"  | line one\n  | line two\n")),
    ?assertNot(has(Text, ~"  | \n\nReply")),
    ?assert(has(Text, ~"magic number: \\0asm")),
    ?assert(has(Text, ~"size       8 bytes")).
