%% Cases: one question for a model, taken from a public source.
%%
%% A case is a directory `<cases>/<track>/<direction>/<name>/' holding
%% `case.config' and, for a reading case, the module it asks about as
%% `module.wasm'. Its id is `<track>/<direction>/<name>', such as
%% `spec/read/add-41'.
%%
%%   read   the model sees a module's bytes as hex and predicts what one call
%%          returns. The reply must be one signed integer.
%%   write  the model gets an English description and a signature, and
%%          replies with a complete module as hex. The module is checked like
%%          a task reply (`wb_check'), against the calls the case records.
%%
%% Every expected answer comes from the source: an upstream assertion, a run
%% of the original binary, or a contest's recorded output. `case.config'
%% also says where in the source the case came from, so another person can
%% find it.
%%
%% Replies to cases are fixtures under `trials/cases/' (model replies) and
%% `examples/cases/' (written by hand), one directory per case and label.
-module(wb_case).

-export([all/1, all/2, load/2, find/2, prompt/2, plan/1, check/2, report/1,
         replies/1, batch/4, batch/5, batch_report/1, read_answer/1, signature/1, call_text/1]).

-export_type([case_/0, read_report/0]).

%% A reading reply is one number; anything longer than this is not one.
-define(MAX_ANSWER_BYTES, 1024).

-type case_() :: #{id := binary(),
                   track := binary(),
                   direction := read | write,
                   name := binary(),
                   dir := file:filename(),
                   export := binary(),
                   params := [atom()],
                   results := [atom()],
                   upstream := [{atom(), term()}],
                   call => [integer()],
                   expected => integer(),
                   module => binary(),
                   module_sha256 => binary(),
                   calls => [{[integer()], integer()}],
                   description => binary(),
                   statement => binary(),
                   template => write | contest,
                   limits => #{fuel => pos_integer(), deadline_ms => pos_integer()}}.

-type read_report() :: #{task := binary(),
                         direction := read,
                         verdict := pass | wrong_answer | malformed_answer | too_large,
                         text_bytes := non_neg_integer(),
                         call := iodata(),
                         expected := integer(),
                         answer => integer(),
                         why => term()}.

%% Every case under `Dir', usually `cases/' in the repository, sorted by id.
-spec all(file:filename()) -> [case_()].
all(Dir) ->
    lists:sort(fun(#{id := A}, #{id := B}) -> A =< B end,
               [C || Track <- subdirs(Dir), C <- all(Dir, Track)]).

%% The cases of one track.
-spec all(file:filename(), string() | binary()) -> [case_()].
all(Dir, Track) ->
    TrackDir = filename:join(Dir, Track),
    lists:sort(fun(#{id := A}, #{id := B}) -> A =< B end,
               [load(Dir, filename:join([TrackDir, D, N]))
                || D <- ["read", "write"], N <- subdirs(filename:join(TrackDir, D)),
                   filelib:is_regular(filename:join([TrackDir, D, N, "case.config"]))]).

%% The case with this id, from `Dir'.
-spec find(file:filename(), binary() | string()) -> {ok, case_()} | {error, not_found}.
find(Dir, Id) ->
    Path = filename:join(Dir, Id),
    case filelib:is_regular(filename:join(Path, "case.config")) of
        true -> {ok, load(Dir, Path)};
        false -> {error, not_found}
    end.

subdirs(Dir) ->
    case file:list_dir(Dir) of
        {ok, Names} -> lists:sort([N || N <- Names, filelib:is_dir(filename:join(Dir, N))]);
        {error, _} -> []
    end.

-spec load(file:filename(), file:filename()) -> case_().
load(_Dir, CaseDir) ->
    Name = filename:basename(CaseDir),
    Direction = filename:basename(filename:dirname(CaseDir)),
    Track = filename:basename(filename:dirname(filename:dirname(CaseDir))),
    {ok, Terms} = file:consult(filename:join(CaseDir, "case.config")),
    C = maps:from_list(Terms),
    Base = #{id => bin([Track, "/", Direction, "/", Name]),
             track => bin(Track),
             direction => case bin(Direction) of
                              <<"read">> -> read;
                              <<"write">> -> write
                          end,
             name => bin(Name),
             dir => CaseDir,
             export => bin(maps:get(export, C)),
             params => maps:get(params, C),
             results => maps:get(results, C),
             upstream => maps:get(upstream, C, [])},
    case Base of
        #{direction := read} ->
            {ok, Module} = file:read_file(filename:join(CaseDir, "module.wasm")),
            Base#{call => maps:get(call, C), expected => maps:get(expected, C), module => Module,
                  module_sha256 => bin(maps:get(module_sha256, C, ""))};
        #{direction := write} ->
            W0 = Base#{calls => maps:get(calls, C)},
            W = case maps:find(limits, C) of
                    {ok, Limits} -> W0#{limits => maps:from_list(Limits)};
                    error -> W0
                end,
            case maps:find(statement, C) of
                {ok, File} ->
                    {ok, Statement} = file:read_file(filename:join(CaseDir, File)),
                    W#{statement => Statement, template => contest};
                error ->
                    W#{description => bin(maps:get(description, C)), template => write}
            end
    end.

bin(Chars) -> unicode:characters_to_binary(Chars).

%% `f(i32, i32) -> i32'.
-spec signature(case_()) -> iodata().
signature(#{export := Export, params := Params, results := [Result]}) ->
    [Export, "(", lists:join(", ", [atom_to_list(P) || P <- Params]), ") -> ",
     atom_to_list(Result)].

%% `f(2147483647, 1)'.
-spec call_text(case_()) -> iodata().
call_text(#{export := Export, call := Args}) ->
    [Export, "(", lists:join(", ", [integer_to_list(A) || A <- Args]), ")"].

%% The exact prompt for a case. `Root' holds `prompts/'.
-spec prompt(file:filename(), case_()) -> binary().
prompt(Root, #{direction := read, module := Module} = C) ->
    fill(Root, "prompts/case-read.txt",
         [{"{{MODULE_HEX}}", string:trim(iolist_to_binary(wb_hex:encode(Module)), trailing)},
          {"{{CALL}}", call_text(C)}]);
prompt(Root, #{direction := write, template := write, description := D} = C) ->
    fill(Root, "prompts/case-write.txt",
         [{"{{SIGNATURE}}", signature(C)}, {"{{DESCRIPTION}}", D}]);
prompt(Root, #{direction := write, template := contest, statement := S, params := Ps} = C) ->
    fill(Root, "prompts/case-contest.txt",
         [{"{{SIGNATURE}}", signature(C)},
          {"{{MAPPING}}", mapping(length(Ps))},
          {"{{STATEMENT}}", string:trim(S)}]).

%% How a contest program's input and output become one call.
mapping(1) ->
    "A program for this problem would read one integer from its input and print one "
    "integer. f receives that integer as its argument and returns the integer the "
    "program would print.";
mapping(N) ->
    io_lib:format("A program for this problem would read ~b integers from its input and "
                  "print one integer. f receives those integers as its arguments, in the "
                  "order the input gives them, and returns the integer the program would "
                  "print.", [N]).

fill(Root, Template, Pairs) ->
    {ok, T} = file:read_file(filename:join(Root, Template)),
    lists:foldl(fun({K, V}, Acc) ->
                        binary:replace(Acc, bin(K), iolist_to_binary(V), [global])
                end, T, Pairs).

%% What a write case's reply is checked against: its recorded calls, with the
%% open profile, since the prompt asks only for the export.
-spec plan(case_()) -> wb_check:plan().
plan(#{direction := write, id := Id, export := Export, params := Ps, results := Rs, calls := Calls} = C) ->
    Expected = maps:from_list(Calls),
    Plan = #{task => Id, export => Export, params => Ps, results => Rs,
             inputs => [Args || {Args, _} <- Calls],
             expected => fun(Args) -> maps:get(Args, Expected) end,
             profile => open},
    case C of
        #{limits := Limits} -> Plan#{limits => Limits};
        _ -> Plan
    end.

-spec check(case_(), binary()) -> read_report() | wb_check:report().
check(#{direction := write} = C, Text) ->
    wb_check:check_plan(plan(C), Text);
check(#{direction := read, id := Id, expected := Want} = C, Text) ->
    R = #{task => Id, direction => read, text_bytes => byte_size(Text),
          call => call_text(C), expected => Want},
    case read_answer(Text) of
        {ok, Want} -> R#{verdict => pass, answer => Want};
        {ok, Got} -> R#{verdict => wrong_answer, answer => Got};
        {error, too_large} -> R#{verdict => too_large, why => {text, byte_size(Text), ?MAX_ANSWER_BYTES}};
        {error, Why} -> R#{verdict => malformed_answer, why => Why}
    end.

%% A reading reply is one signed decimal integer, with optional whitespace
%% around it. Nothing is extracted from a longer reply: "The answer is 3" is
%% not an answer, as prose around hex is not a module.
-spec read_answer(binary()) -> {ok, integer()} | {error, too_large | {not_a_number, binary()}}.
read_answer(Text) when byte_size(Text) > ?MAX_ANSWER_BYTES ->
    {error, too_large};
read_answer(Text) ->
    T = string:trim(Text),
    case re:run(T, "^[+-]?[0-9]+$", [unicode]) of
        {match, _} -> {ok, binary_to_integer(strip_plus(T))};
        nomatch -> {error, {not_a_number, first_line(T)}}
    end.

strip_plus(<<"+", Rest/binary>>) -> Rest;
strip_plus(T) -> T.

first_line(T) ->
    [Line | _] = string:split(T, "\n"),
    case string:length(Line) > 60 of
        true -> [string:slice(Line, 0, 60), "..."];
        false -> Line
    end.

%% The lines `check' prints. A write case prints as a task reply does.
-spec report(read_report() | wb_check:report()) -> iodata().
report(#{direction := read} = R) ->
    [line("call", maps:get(call, R)),
     case R of
         #{answer := A} -> line("answer", integer_to_list(A));
         #{verdict := too_large, why := {text, N, Max}} ->
             line("answer", io_lib:format("~b bytes of reply; the limit is ~b", [N, Max]));
         #{why := {not_a_number, Start}} ->
             line("answer", ["not one integer: the reply starts \"", Start, "\""])
     end,
     line("expected", integer_to_list(maps:get(expected, R))),
     line("verdict", atom_to_list(maps:get(verdict, R)))];
report(R) ->
    wb_report:report(R).

line(Tag, Text) ->
    [io_lib:format("  ~-8s ", [Tag]), Text, $\n].

%% The saved replies to cases: `<Root>/<kind>/cases/<case id>/<label>/'.
-spec replies(file:filename()) -> [map()].
replies(Root) ->
    [reply(Kind, Root, CaseId, Dir)
     || Kind <- [examples, trials],
        Base <- [filename:join([Root, Kind, "cases"])],
        Track <- subdirs(Base),
        Direction <- subdirs(filename:join(Base, Track)),
        Name <- subdirs(filename:join([Base, Track, Direction])),
        CaseId <- [bin([Track, "/", Direction, "/", Name])],
        Label <- subdirs(filename:join([Base, Track, Direction, Name])),
        Dir <- [filename:join([Base, Track, Direction, Name, Label])]].

%% A reply still being recorded has no `fixture.config' yet; it reads as an
%% empty configuration, which the tests refuse.
reply(Kind, _Root, CaseId, Dir) ->
    Terms = case file:consult(filename:join(Dir, "fixture.config")) of
                {ok, T} -> T;
                {error, _} -> []
            end,
    #{kind => Kind, case_id => CaseId, label => bin(filename:basename(Dir)), dir => Dir,
      reply => read_file(filename:join(Dir, "reply.txt")),
      prompt => read_file(filename:join(Dir, "prompt.txt")),
      config => maps:from_list(Terms)}.

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> Bin;
        {error, enoent} -> missing
    end.

%% A batch: every case of one track, and the model reply saved under `Label'
%% for each, under `<Root>/trials/cases/'. Cases with no saved reply are
%% counted as missing, not as failures. The track's `selection.config' says
%% how many source items were examined and why some were skipped.
-spec batch(file:filename(), file:filename(), binary() | string(), binary() | string()) -> map().
batch(Root, CasesDir, Track, Label) ->
    batch(filename:join([Root, "trials", "cases"]), CasesDir, Track, Label, []).

%% The same, with the replies under `RepliesDir' instead, such as the
%% replies of a corpus run under `trials/corpus/'.
-spec batch(file:filename(), file:filename(), binary() | string(), binary() | string(), []) -> map().
batch(RepliesDir, CasesDir, Track, Label, []) ->
    Cases = all(CasesDir, Track),
    Checked = [{C, reply_for(RepliesDir, C, Label)} || C <- Cases],
    Selection = case file:consult(filename:join([CasesDir, Track, "selection.config"])) of
                    {ok, Terms} -> maps:from_list(Terms);
                    {error, _} -> #{}
                end,
    #{track => bin(Track), label => bin(Label), selection => Selection,
      read => direction_summary(read, Checked), write => direction_summary(write, Checked)}.

reply_for(RepliesDir, #{id := Id} = C, Label) ->
    Path = filename:join([RepliesDir, Id, Label, "reply.txt"]),
    case file:read_file(Path) of
        {ok, Text} -> {ok, check(C, Text)};
        {error, enoent} -> missing
    end.

direction_summary(Direction, Checked) ->
    Mine = [{C, R} || {#{direction := D} = C, R} <- Checked, D =:= Direction],
    Attempted = [{C, R} || {C, {ok, R}} <- Mine],
    Passed = [X || {_, #{verdict := pass}} = X <- Attempted],
    Failed = [X || {_, #{verdict := V}} = X <- Attempted, V =/= pass],
    Base = #{cases => length(Mine), attempted => length(Attempted),
             missing => length(Mine) - length(Attempted), passed => length(Passed),
             failing => [first_failure(X) || X <- Failed]},
    case Direction of
        read -> Base;
        write -> Base#{valid => length([X || {_, #{verdict := V}} = X <- Attempted, valid(V)])}
    end.

%% A module erlang_wasm decoded and validated, whatever happened next.
valid(V) -> lists:member(V, [pass, wrong_answer, execution_failure, interface_mismatch]).

%% The case, its verdict, and one input with the expected and actual output
%% where there is one.
first_failure({#{id := Id}, #{direction := read, verdict := V} = R}) ->
    #{id => Id, verdict => V, call => maps:get(call, R), expected => maps:get(expected, R),
      answer => maps:get(answer, R, none)};
first_failure({#{id := Id}, #{verdict := V} = R}) ->
    #{id => Id, verdict => V,
      example => case maps:get(wrong, R, []) of
                     [{X, Want, Got} | _] -> {X, Want, Got};
                     [] -> case maps:get(failures, R, []) of
                               [{X, E} | _] -> {X, E};
                               [] -> none
                           end
                 end}.

-spec batch_report(map()) -> iodata().
batch_report(#{track := Track, label := Label, selection := S, read := Rd, write := Wr}) ->
    [line("track", [Track, ", replies labelled ", Label]),
     source_lines(S),
     case Rd of
         #{cases := 0} -> [];
         _ -> [line("read", io_lib:format("~b correct predictions out of ~b attempted calls",
                                          [maps:get(passed, Rd), maps:get(attempted, Rd)])),
               line("", io_lib:format("~b case~s with no saved reply",
                                      [maps:get(missing, Rd), plural(maps:get(missing, Rd))])),
               [failure_line(F) || F <- maps:get(failing, Rd)]]
     end,
     case Wr of
         #{cases := 0} -> [];
         _ -> [line("write", io_lib:format("~b of ~b first replies were valid modules",
                                           [maps:get(valid, Wr), maps:get(attempted, Wr)])),
               line("", io_lib:format("~b of ~b passed every behavioral check",
                                      [maps:get(passed, Wr), maps:get(attempted, Wr)])),
               line("", io_lib:format("~b case~s with no saved reply",
                                      [maps:get(missing, Wr), plural(maps:get(missing, Wr))])),
               [failure_line(F) || F <- maps:get(failing, Wr)]]
     end].

source_lines(#{examined := E, usable := U} = S) ->
    Skipped = maps:get(skipped, S, []),
    [line("source", io_lib:format("~b examined, ~b usable, ~b skipped",
                                  [E, U, lists:sum([N || {_, N} <- Skipped])])),
     [line("", io_lib:format("skipped ~b: ~ts", [N, Why])) || {Why, N} <- Skipped]];
source_lines(_) ->
    [].

failure_line(#{id := Id, verdict := V, call := Call, expected := Want, answer := Got}) ->
    line("failed", io_lib:format("~ts (~p): ~ts, expected ~b, answered ~ts",
                                 [Id, V, Call, Want, case Got of
                                                         none -> "no number";
                                                         _ -> integer_to_list(Got)
                                                     end]));
failure_line(#{id := Id, verdict := V, example := {X, Want, Got}}) ->
    line("failed", io_lib:format("~ts (~p): input ~ts, expected ~b, got ~b",
                                 [Id, V, wb_report:input(X), Want, Got]));
failure_line(#{id := Id, verdict := V, example := {instantiate, Why}}) ->
    line("failed", io_lib:format("~ts (~p): the module could not be instantiated: ~0P",
                                 [Id, V, Why, 8]));
failure_line(#{id := Id, verdict := V, example := {X, E}}) ->
    line("failed", io_lib:format("~ts (~p): input ~ts, ~ts",
                                 [Id, V, wb_report:input(X), wb_report:outcome(error_of(E))]));
failure_line(#{id := Id, verdict := V}) ->
    line("failed", io_lib:format("~ts (~p)", [Id, V])).

error_of(not_run) -> not_run;
error_of(E) -> {error, E}.

plural(1) -> "";
plural(_) -> "s".
