%% The command line: `bin/wasm-bytes <command>'.
%%
%%   replay                             trace one model reply and five outcomes
%%   demo                               replay every saved reply
%%   trace TRIAL [--wasm FILE]          prompt, reply and decoded module of a trial
%%   compare TASK REPLY [--record DIR]  run a reply in erlang_wasm and Wasmtime
%%   check write|digits REPLY           check a reply to a one-prompt task
%%   check revise REPLY --base REPLY    check a task 2 reply against its base
%%   prompt write|digits [--guided]     print a one-prompt task's prompt
%%   prompt revise --base REPLY         print the task 2 prompt for a base
%%
%% REPLY is a file, or `-' for standard input.
-module(wasm_bytes).

-export([main/1, run/2, demo/1, render_revise_prompt/2, render_prompt/3, render_prompt/4]).

-define(PLACEHOLDER, <<"{{MODULE_HEX}}">>).

%% Tasks with one prompt, and tasks that revise another task's reply.
-define(ONE_PROMPT(T), (T =:= "write" orelse T =:= "digits" orelse T =:= "pan" orelse T =:= "ui")).
-define(REVISION(T), (T =:= "revise" orelse T =:= "reverse")).

-spec main([string()]) -> no_return().
main(Args) ->
    erlang:halt(run(Args, standard_error)).

%% Runs one command and answers its exit status. Errors go to `Err', an IO
%% device; the tests pass one that collects them.
-spec run([string()], io:device()) -> 0 | 1 | 2.
run(Args, Err) ->
    {ok, _} = application:ensure_all_started(wasm),
    put(wasm_bytes_err, Err),
    try command(Args)
    catch
        throw:{usage, Msg} ->
            err([Msg, "\n\n", usage()]),
            2;
        throw:{fail, Msg} ->
            err([Msg, "\n"]),
            2
    after
        erase(wasm_bytes_err)
    end.

err(Chars) ->
    io:put_chars(case get(wasm_bytes_err) of
                     undefined -> standard_error;
                     Dev -> Dev
                 end, Chars).

command(["replay"]) ->
    {Out, Ok} = wb_replay:run(root()),
    io:put_chars(Out),
    case Ok of
        true -> 0;
        false -> 1
    end;
command(["demo"]) ->
    demo(root());
command(["trace", Dir]) ->
    trace(Dir, undefined);
command(["trace", Dir, "--wasm", File]) ->
    trace(Dir, File);
command(["compare", Task, Reply]) ->
    compare(task(Task), Reply, undefined);
command(["compare", Task, Reply, "--record", Dir]) ->
    compare(task(Task), Reply, Dir);
command(["check", "ui", Reply | Opts]) ->
    ui_check(Reply, Opts);
command(["check", Task, Reply]) when ?ONE_PROMPT(Task) ->
    R = wb_check:check(task(Task), input(Reply)),
    io:put_chars(wb_report:report(R)),
    exit_code(R);
command(["check", Task, Reply, "--base", Base]) when ?REVISION(Task) ->
    check_revise(task(Task), Reply, Base);
command(["check", Task, "--base", Base, Reply]) when ?REVISION(Task) ->
    check_revise(task(Task), Reply, Base);
command(["prompt", Task]) when ?ONE_PROMPT(Task) ->
    io:put_chars(prompt_file(root(), task(Task))),
    0;
command(["prompt", Task, "--guided"]) when ?ONE_PROMPT(Task) ->
    case wb_task:prompt(task(Task), guided) of
        {ok, Path} ->
            {ok, Bin} = file:read_file(filename:join(root(), Path)),
            io:put_chars(Bin),
            0;
        {error, no_guided_prompt} ->
            throw({usage, ["wasm-bytes: the ", Task, " task has no guided prompt"]})
    end;
command(["prompt", Task, "--base", Base]) when ?REVISION(Task) ->
    revision_prompt(Task, Base, baseline);
command(["prompt", Task, "--base", Base, "--guided"]) when ?REVISION(Task) ->
    revision_prompt(Task, Base, guided);
command(["prompt", Task, "--guided", "--base", Base]) when ?REVISION(Task) ->
    revision_prompt(Task, Base, guided);
command(["pan-demo" | Opts]) ->
    pan_demo(Opts);
command(["help"]) ->
    io:put_chars(usage()),
    0;
command(_) ->
    throw({usage, "wasm-bytes: unknown command"}).

revision_prompt(Task, Base, Variant) ->
    case render_prompt(root(), task(Task), input(Base), Variant) of
        {ok, Prompt} ->
            io:put_chars(Prompt),
            0;
        {error, Report} ->
            {ok, BaseTask} = wb_task:base(task(Task)),
            err(wb_report:base_refused(list_to_binary(Base), Report, BaseTask)),
            1
    end.

usage() ->
    "usage: bin/wasm-bytes replay\n"
    "       bin/wasm-bytes demo\n"
    "       bin/wasm-bytes trace TRIAL-DIRECTORY [--wasm FILE]\n"
    "       bin/wasm-bytes compare TASK REPLY [--record DIRECTORY]\n"
    "       bin/wasm-bytes check write|digits|pan REPLY\n"
    "       bin/wasm-bytes check ui PAGE [--original REPLY --reversed REPLY]\n"
    "       bin/wasm-bytes check revise|reverse REPLY --base REPLY\n"
    "       bin/wasm-bytes prompt write|digits|pan|ui [--guided]\n"
    "       bin/wasm-bytes prompt revise|reverse --base REPLY [--guided]\n"
    "       bin/wasm-bytes pan-demo [--original REPLY --reversed REPLY] [--no-open]\n"
    "TASK is write, revise, digits, pan or reverse.\n"
    "REPLY is a file holding a model's reply, or - for standard input.\n".

check_revise(Task, Reply, Base) ->
    case wb_check:check_revision(Task, input(Base), input(Reply)) of
        {ok, Rev} ->
            io:put_chars(wb_report:revision(Base, Rev)),
            exit_code(maps:get(revised, Rev));
        {error, {base_not_accepted, Report}} ->
            {ok, BaseTask} = wb_task:base(Task),
            io:put_chars(wb_report:base_refused(list_to_binary(Base), Report, BaseTask)),
            1
    end.

%% A generated page, checked in a browser with the recorded pan modules.
ui_check(Reply, Opts) ->
    {O, R} = wb_pan_demo:default_replies(),
    {Original, Reversed, _} = pan_demo_opts(Opts, filename:join(root(), O), filename:join(root(), R), false),
    case wb_ui:check(root(), input(Reply), {Original, Reversed}) of
        {ok, Report} ->
            io:put_chars(wb_ui:report(Report)),
            exit_code(Report);
        {error, {missing, What}} ->
            throw({fail, io_lib:format("check ui needs Node and Chrome; ~p was not found. "
                                       "Set NODE or CHROME to its path.", [What])});
        {error, Why} ->
            throw({fail, io_lib:format("the pan modules do not pass: ~0p", [Why])})
    end.

pan_demo(Opts) ->
    {DefaultOriginal, DefaultReversed} = wb_pan_demo:default_replies(),
    {Original, Reversed, Open} = pan_demo_opts(Opts, filename:join(root(), DefaultOriginal),
                                               filename:join(root(), DefaultReversed), true),
    Out = filename:join([root(), "_build", "pan-demo"]),
    case wb_pan_demo:build(root(), Original, Reversed, Out) of
        {ok, Index} ->
            io:format("  original   ~ts~n  reversed   ~ts~n  page       ~ts~n",
                      [relative(Original), relative(Reversed), Index]),
            case Open of
                true -> open_page(Index);
                false -> ok
            end,
            0;
        {error, {original_refused, Report}} ->
            err(wb_report:base_refused(relative(Original), Report, pan)),
            1;
        {error, {reversed_refused, Report}} ->
            err([relative(Reversed), " does not pass the reverse task:\n", wb_report:report(Report)]),
            1
    end.

pan_demo_opts([], O, R, Open) -> {O, R, Open};
pan_demo_opts(["--original", P | Rest], _, R, Open) -> pan_demo_opts(Rest, P, R, Open);
pan_demo_opts(["--reversed", P | Rest], O, _, Open) -> pan_demo_opts(Rest, O, P, Open);
pan_demo_opts(["--no-open" | Rest], O, R, _) -> pan_demo_opts(Rest, O, R, false);
pan_demo_opts(_, _, _, _) -> throw({usage, "wasm-bytes: pan-demo takes --original, --reversed and --no-open"}).

%% The system's own opener, without a shell.
open_page(Path) ->
    case [E || E <- [os:find_executable(C) || C <- ["open", "xdg-open"]], E =/= false] of
        [Exe | _] ->
            Port = open_port({spawn_executable, Exe}, [{args, [Path]}, exit_status]),
            receive {Port, {exit_status, _}} -> ok after 5000 -> ok end;
        [] ->
            io:format("  open the page in a browser~n")
    end.

trace(Dir, Wasm) ->
    case wb_trace:load(Dir) of
        {ok, T} ->
            io:put_chars(wb_trace:trace(T)),
            case {Wasm, T} of
                {undefined, _} ->
                    0;
                {_, #{decoded := {ok, Bytes}}} ->
                    ok = file:write_file(Wasm, Bytes),
                    io:format("  wrote      ~ts~n", [Wasm]),
                    0;
                {_, _} ->
                    1
            end;
        {error, {Path, Why}} ->
            throw({fail, io_lib:format("cannot read ~ts: ~ts", [Path, file:format_error(Why)])})
    end.

%% Exits 0 when both engines match the reference on every input, 1 when they
%% do not, 2 when Wasmtime is missing or the reply is not hex.
compare(Task, Reply, RecordDir) ->
    case wb_compare:compare(Task, input(Reply), relative(Reply)) of
        {ok, C} ->
            io:put_chars(wb_compare:report(C)),
            case RecordDir of
                undefined -> ok;
                _ -> io:format("  ~-12s ~ts~n", ["recorded", wb_compare:record(C, RecordDir)])
            end,
            case maps:get(verdict, C) of
                pass -> 0;
                _ -> 1
            end;
        {error, wasmtime_not_found} ->
            throw({fail, "wasmtime not found: install it (https://wasmtime.dev) or set WASMTIME "
                         "to its path. Nothing else in wasm-bytes needs it."});
        {error, {malformed_hex, Why}} ->
            throw({fail, io_lib:format("the reply is not hex: ~0p", [Why])})
    end.

task("write") -> write;
task("revise") -> revise;
task("digits") -> digits;
task("pan") -> pan;
task("reverse") -> reverse;
task("ui") -> ui;
task(_) -> throw({usage, "wasm-bytes: the task is write, revise, digits, pan or reverse"}).

%% A reply's path as the repository names it, when it is inside it.
relative(Path) ->
    Abs = filename:absname(Path),
    Root = filename:absname(root()) ++ "/",
    unicode:characters_to_binary(case lists:prefix(Root, Abs) of
                                     true -> lists:nthtail(length(Root), Abs);
                                     false -> Path
                                 end).

%% 0 the reply passes, 1 it does not, 2 the runner could not judge it.
exit_code(#{verdict := pass}) -> 0;
exit_code(#{verdict := runner_error}) -> 2;
exit_code(_) -> 1.

%% The task 2 prompt for the bytes accepted in task 1. The base must pass task
%% 1: the prompt shows the model the exact bytes that were accepted.
-spec render_revise_prompt(file:filename(), binary()) -> {ok, iodata()} | {error, wb_check:report()}.
render_revise_prompt(Root, BaseText) ->
    render_prompt(Root, revise, BaseText).

%% The prompt of a task that revises another, for a base reply that passes
%% the base task.
-spec render_prompt(file:filename(), wb_task:name(), binary()) ->
          {ok, iodata()} | {error, wb_check:report()}.
render_prompt(Root, Task, BaseText) ->
    render_prompt(Root, Task, BaseText, baseline).

-spec render_prompt(file:filename(), wb_task:name(), binary(), baseline | guided) ->
          {ok, iodata()} | {error, wb_check:report()}.
render_prompt(Root, Task, BaseText, Variant) ->
    {ok, BaseTask} = wb_task:base(Task),
    case wb_check:check(BaseTask, BaseText) of
        #{verdict := pass, bytes := Bytes} ->
            {ok, Path} = wb_task:prompt(Task, Variant),
            {ok, Template} = file:read_file(filename:join(Root, Path)),
            Hex = string:trim(iolist_to_binary(wb_hex:encode(Bytes)), trailing),
            {ok, binary:replace(Template, ?PLACEHOLDER, Hex)};
        Report ->
            {error, Report}
    end.

prompt_file(Root, Task) ->
    #{prompt := Path} = wb_task:get(Task),
    {ok, Bin} = file:read_file(filename:join(Root, Path)),
    Bin.

input("-") ->
    ok = io:setopts(standard_io, [binary]),
    read_stdin([]);
input(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> Bin;
        {error, Why} -> throw({fail, io_lib:format("cannot read ~ts: ~ts", [Path, file:format_error(Why)])})
    end.

read_stdin(Acc) ->
    case io:get_chars(standard_io, '', 65536) of
        eof -> iolist_to_binary(lists:reverse(Acc));
        {error, Why} -> throw({fail, io_lib:format("cannot read standard input: ~p", [Why])});
        Data -> read_stdin([Data | Acc])
    end.

root() ->
    case os:getenv("WASM_BYTES_ROOT") of
        false -> {ok, Cwd} = file:get_cwd(), Cwd;
        Root -> Root
    end.

%%% ------------------------------------------------------------------ demo ---

%% Replays every fixture, prints what each one shows, and answers 0 only when
%% every verdict is the one its fixture is labelled with and every fixture is
%% what its provenance says it is.
-spec demo(file:filename()) -> 0 | 1.
demo(Root) ->
    Fixtures = wb_fixture:all(Root),
    #{fuel := Fuel, deadline_ms := Deadline, max_module_bytes := MaxBytes} = wb_check:limits(),
    io:format("wasm-bytes demo: erlang_wasm ~ts, ~b inputs per retry candidate and ~b per "
              "digit_sum candidate, fuel ~b, deadline ~b ms, at most ~b module bytes~n~n",
              [vsn(), length(wb_task:inputs(write)), length(wb_task:inputs(digits)),
               Fuel, Deadline, MaxBytes]),
    Rows = [replay(Root, F) || F <- Fixtures],
    io:put_chars(summary(Rows)),
    case lists:all(fun(#{ok := Ok}) -> Ok end, Rows) of
        true -> 0;
        false -> 1
    end.

replay(Root, #{task := Task, label := Label, kind := Kind, config := C} = F) ->
    Expect = maps:get(expect, C, undefined),
    Problems = wb_fixture:problems(F),
    io:format("== ~ts/~ts/~ts  (~ts; labelled ~p)~n",
              [Kind, Task, Label, provenance(F), Expect]),
    [io:format("   ~ts~n", [Line]) || Line <- note_lines(C)],
    [io:format("   PROVENANCE: ~ts~n", [P]) || P <- Problems],
    Got = case {Problems, Task} of
              {[_ | _], _} ->
                  undefined;
              {[], ui} ->
                  case wb_ui:check(Root, maps:get(reply, F)) of
                      {ok, R} ->
                          io:put_chars(wb_ui:report(R)),
                          maps:get(verdict, R);
                      {error, {missing, What}} ->
                          io:format("  skipped: needs Node and Chrome (~p not found)~n", [What]),
                          skipped
                  end;
              {[], _} ->
                  case wb_task:base(Task) of
                      none ->
                          R = wb_check:check(Task, maps:get(reply, F)),
                          io:put_chars(wb_report:report(R)),
                          maps:get(verdict, R);
                      {ok, _} ->
                          replay_revision(Root, F)
                  end
          end,
    Ok = Problems =:= [] andalso (Got =:= Expect orelse Got =:= skipped),
    io:format("   => ~ts~n~n", [case Ok of
                                     true -> "as labelled";
                                     false -> io_lib:format("NOT as labelled: got ~p", [Got])
                                 end]),
    #{name => [atom_to_list(Kind), "/", atom_to_list(Task), "/", Label],
      source => maps:get(source, C, undefined), trial => wb_fixture:is_trial(F),
      expect => Expect, got => Got, ok => Ok}.

replay_revision(Root, #{task := Task} = F) ->
    case wb_fixture:base_reply(Root, F) of
        {ok, BaseName, BaseText} ->
            case wb_check:check_revision(Task, BaseText, maps:get(reply, F)) of
                {ok, Rev} ->
                    io:put_chars(wb_report:revision(BaseName, Rev)),
                    maps:get(verdict, maps:get(revised, Rev));
                {error, {base_not_accepted, Report}} ->
                    {ok, BaseTask} = wb_task:base(Task),
                    io:put_chars(wb_report:base_refused(BaseName, Report, BaseTask)),
                    base_not_accepted
            end;
        {error, Why} ->
            io:format("   cannot read the base: ~p~n", [Why]),
            undefined
    end.

provenance(#{config := #{source := model_trial} = C}) ->
    io_lib:format("model trial: ~ts via ~ts, recorded ~ts",
                  [maps:get(model, C, "?"), maps:get(interface, C, "?"),
                   maps:get(recorded_on, C, "?")]);
provenance(#{config := #{source := hand_written}}) ->
    "hand-written, not a model trial";
provenance(_) ->
    "no source recorded".

note_lines(#{note := Note}) ->
    string:split(string:trim(unicode:characters_to_binary(Note)), "\n", all);
note_lines(_) ->
    [].

summary(Rows) ->
    Trials = length([R || #{trial := true} = R <- Rows]),
    Matched = length([R || #{ok := true} = R <- Rows]),
    ["Summary\n",
     io_lib:format("  ~-44s ~-14s ~-20s ~-20s~n", ["fixture", "source", "labelled", "got"]),
     [io_lib:format("  ~-44ts ~-14s ~-20s ~-20s ~s~n",
                    [Name, source(S), atom(E), atom(G), case Ok of true -> "ok"; false -> "MISMATCH" end])
      || #{name := Name, source := S, expect := E, got := G, ok := Ok} <- Rows],
     io_lib:format("~n  ~b of ~b fixtures as labelled.~n", [Matched, length(Rows)]),
     io_lib:format("  Model trials recorded: ~b. ~ts~n",
                   [Trials, case Trials of
                                0 -> "Every fixture above is hand-written; none is evidence of what a model can do.";
                                _ -> "Only those count as evidence of what a model can do."
                            end])].

source(hand_written) -> "hand-written";
source(model_trial) -> "model trial";
source(Other) -> atom(Other).

atom(A) when is_atom(A) -> atom_to_list(A);
atom(A) -> io_lib:format("~p", [A]).

vsn() ->
    case application:get_key(wasm, vsn) of
        {ok, V} -> V;
        undefined -> "?"
    end.
