%% Saved replies, and where each came from.
%%
%% A fixture is a directory `<kind>/<task>/<label>/' holding:
%%
%%   reply.txt       the raw reply, exactly as received or written
%%   fixture.config  Erlang terms: provenance, the expected verdict, a note
%%   prompt.txt      the exact prompt sent (required for a model trial)
%%   module.wat      for a valid module, the text it was assembled from
%%
%% `examples/' holds hand-written fixtures. `trials/' holds model trials. A
%% fixture counts as a model trial only when its prompt, its raw reply and the
%% model's identity were all recorded; `problems/1' says what is missing.
-module(wb_fixture).

-export([all/1, load/3, problems/1, base_reply/2, is_trial/1]).

-export_type([fixture/0]).

-type fixture() :: #{kind := examples | trials,
                     task := wb_task:name(),
                     label := binary(),
                     dir := file:filename(),
                     reply := binary() | missing,
                     prompt := binary() | missing,
                     config := #{atom() => term()}}.

-spec all(file:filename()) -> [fixture()].
all(Root) ->
    [F || Kind <- [examples, trials],
          Task <- wb_task:names(),
          F <- in(Root, Kind, Task)].

in(Root, Kind, Task) ->
    Dir = filename:join([Root, Kind, Task]),
    case file:list_dir(Dir) of
        {ok, Names} ->
            [load(Root, Kind, filename:join(Dir, N))
             || N <- lists:sort(Names), filelib:is_dir(filename:join(Dir, N))];
        {error, enoent} ->
            []
    end.

-spec load(file:filename(), examples | trials, file:filename()) -> fixture().
load(_Root, Kind, Dir) ->
    TaskDir = unicode:characters_to_binary(filename:basename(filename:dirname(Dir))),
    Task = case [T || T <- wb_task:names(), atom_to_binary(T) =:= TaskDir] of
               [T] -> T;
               [] -> error({unknown_task, Dir})
           end,
    Config = case file:consult(filename:join(Dir, "fixture.config")) of
                 {ok, Terms} -> maps:from_list(Terms);
                 {error, Why} -> error({bad_fixture_config, Dir, Why})
             end,
    #{kind => Kind, task => Task,
      label => unicode:characters_to_binary(filename:basename(Dir)),
      dir => Dir,
      reply => read(filename:join(Dir, "reply.txt")),
      prompt => read(filename:join(Dir, "prompt.txt")),
      config => Config}.

read(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> Bin;
        {error, enoent} -> missing
    end.

-spec is_trial(fixture()) -> boolean().
is_trial(#{config := #{source := model_trial}} = F) -> problems(F) =:= [];
is_trial(_) -> false.

%% What stops a fixture from being what it says it is. A hand-written fixture
%% must say what it demonstrates; a model trial must have its prompt, its raw
%% reply, the model and how it was reached, and the date it was recorded.
-spec problems(fixture()) -> [iodata()].
problems(#{kind := Kind, task := Task, reply := Reply, prompt := Prompt, config := C}) ->
    Source = maps:get(source, C, undefined),
    [["reply.txt is missing"] || Reply =:= missing]
    ++ [["fixture.config has no expect"] || not is_map_key(expect, C)]
    ++ [["a revise fixture must name its base"] || Task =:= revise, not is_map_key(base, C)]
    ++ case {Kind, Source} of
           {examples, hand_written} ->
               [["a hand-written fixture needs a note"] || not filled(maps:get(note, C, ""))];
           {trials, model_trial} ->
               [["prompt.txt is missing"] || Prompt =:= missing]
               ++ [[atom_to_list(K), " is not recorded"]
                   || K <- [model, interface, recorded_on], not filled(maps:get(K, C, ""))];
           {examples, _} ->
               [["examples/ holds hand-written fixtures only (source must be hand_written)"]];
           {trials, _} ->
               [["trials/ holds model trials only (source must be model_trial)"]]
       end.

filled(V) when is_binary(V) -> string:trim(V) =/= <<>>;
filled(V) when is_list(V) -> string:trim(V) =/= "";
filled(_) -> false.

%% The task 1 reply a revise fixture was given, named by its `base' entry:
%% `"write/accepted"' is that fixture in the same kind of directory.
-spec base_reply(file:filename(), fixture()) -> {ok, binary(), binary()} | {error, term()}.
base_reply(Root, #{kind := Kind, config := #{base := Base}}) ->
    Path = filename:join([Root, Kind, Base, "reply.txt"]),
    case file:read_file(Path) of
        {ok, Bin} -> {ok, unicode:characters_to_binary(Base), Bin};
        {error, Why} -> {error, {Path, Why}}
    end;
base_reply(_Root, _F) ->
    {error, no_base}.
