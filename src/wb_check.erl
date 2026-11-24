%% Checks one model reply against a task, stage by stage.
%%
%%   1. size: the reply text, then the decoded bytes, are bounded
%%   2. hex: the reply is decoded, and nothing else is done to it
%%   3. wasm: erlang_wasm decodes and validates the bytes (`wasm:compile/1')
%%   4. profile: the module has the shape the task allows (`wb_profile')
%%   5. calls: the export runs on every input in a fresh worker (`wb_exec')
%%   6. answers: each result is compared with the reference (`wb_task')
%%
%% The first stage that fails gives the verdict. The bytes that reach
%% erlang_wasm are exactly the bytes the reply spelled out: no length is
%% recomputed and no byte is added.
-module(wb_check).

-export([check/2, check_plan/2, check_revision/2, check_revision/3, limits/0]).

-export_type([verdict/0, report/0, revision/0, plan/0]).

-define(MAX_TEXT_BYTES, 65_536).
-define(MAX_MODULE_BYTES, 4_096).

-type verdict() :: pass
                 | too_large
                 | malformed_hex
                 | malformed_wasm
                 | invalid
                 | interface_mismatch
                 | execution_failure
                 | wrong_answer
                 | runner_error.

%% What a reply is checked against. A task's plan comes from `wb_task'; a
%% write case builds its own from its recorded calls (`wb_case'). `strict' is
%% the task profile: one function and nothing else. `open' asks only for the
%% export, with its signature, and no imports.
-type plan() :: #{task := wb_task:name() | binary(),
                  export := binary(),
                  params := [atom()],
                  results := [atom()],
                  inputs := [wb_exec:input()],
                  expected := fun((wb_exec:input()) -> integer()),
                  profile := strict | open,
                  limits => #{fuel => pos_integer(), deadline_ms => pos_integer()}}.

-type report() :: #{task := wb_task:name() | binary(),
                    verdict := verdict(),
                    why => term(),
                    text_bytes := non_neg_integer(),
                    bytes => binary(),
                    plan => #{atom() => term()},
                    results => [{wb_exec:input(), wb_exec:outcome()}],
                    failures => [{wb_exec:input() | instantiate, term()}],
                    wrong => [{wb_exec:input(), integer(), integer()}]}.

-type revision() :: #{base := report(),
                      revised := report(),
                      hunks => [wb_diff:hunk()],
                      changes => [{integer(), wb_exec:outcome(), wb_exec:outcome()}],
                      intended := [{integer(), 0 | 1, 0 | 1}]}.

-spec limits() -> map().
limits() ->
    maps:merge(#{max_text_bytes => ?MAX_TEXT_BYTES,
                 max_module_bytes => ?MAX_MODULE_BYTES},
               wb_exec:limits()).

-spec check(wb_task:name(), binary()) -> report().
check(Task, Text) ->
    #{export := Export, params := Params, results := Results} = wb_task:get(Task),
    check_plan(#{task => Task, export => Export, params => Params, results => Results,
                 inputs => wb_task:inputs(Task), expected => fun(X) -> wb_task:expected(Task, X) end,
                 profile => strict},
               Text).

%% The same stages against any plan. A case's report also carries the plan's
%% interface and input count, so the report can be printed without `wb_task'.
-spec check_plan(plan(), binary()) -> report().
check_plan(#{task := Task} = Plan, Text) ->
    R0 = #{task => Task, text_bytes => byte_size(Text)},
    R = case is_atom(Task) of
            true -> R0;
            false -> R0#{plan => maps:merge(maps:with([export, params, results, profile, limits], Plan),
                                            #{inputs => length(maps:get(inputs, Plan))})}
        end,
    try stages(Plan, Text, R)
    catch
        Class:Reason:Stack ->
            %% A crash here is a bug in the runner or in erlang_wasm, not
            %% something the candidate did; it is reported as such.
            R#{verdict => runner_error, why => {Class, Reason, Stack}}
    end.

stages(_Plan, Text, R) when byte_size(Text) > ?MAX_TEXT_BYTES ->
    R#{verdict => too_large, why => {text, byte_size(Text), ?MAX_TEXT_BYTES}};
stages(Plan, Text, R) ->
    case wb_hex:decode(Text) of
        {error, Why} ->
            R#{verdict => malformed_hex, why => Why};
        {ok, Bytes} when byte_size(Bytes) > ?MAX_MODULE_BYTES ->
            R#{verdict => too_large, bytes => Bytes,
               why => {bytes, byte_size(Bytes), ?MAX_MODULE_BYTES}};
        {ok, Bytes} ->
            compile(Plan, Bytes, R#{bytes => Bytes})
    end.

compile(Plan, Bytes, R) ->
    case wasm:compile(Bytes) of
        {error, #{class := malformed} = E} ->
            R#{verdict => malformed_wasm, why => E};
        {error, #{class := invalid} = E} ->
            R#{verdict => invalid, why => E};
        {error, E} ->
            R#{verdict => runner_error, why => E};
        {ok, Module} ->
            profile(Plan, Bytes, Module, R)
    end.

profile(Plan, Bytes, Module, R) ->
    case profile_check(Plan, Bytes) of
        {error, Violations} ->
            R#{verdict => interface_mismatch, why => Violations};
        ok ->
            run(Plan, Module, R)
    end.

profile_check(#{profile := strict, task := Task}, Bytes) ->
    wb_profile:check(Bytes, Task);
profile_check(#{profile := open, export := Export, params := Params, results := Results}, Bytes) ->
    wb_profile:check_open(Bytes, Export, {Params, Results}).

run(#{export := Export, inputs := Inputs} = Plan, Module, R) ->
    case wb_exec:run(Module, Export, Inputs, maps:get(limits, Plan, #{})) of
        {error, {instantiate, Why}} ->
            R#{verdict => execution_failure, results => [],
               failures => [{instantiate, Why}], wrong => []};
        {ok, Results} ->
            judge(Plan, Results, R#{results => Results})
    end.

judge(#{expected := Expected}, Results, R) ->
    Failures = [{X, E} || {X, {error, E}} <- Results] ++ [{X, not_run} || {X, not_run} <- Results],
    Answers = [{X, Expected(X), Got} || {X, {ok, Got}} <- Results],
    Wrong = [A || {_, Want, Got} = A <- Answers, Want =/= Got],
    Verdict = if
                  Failures =/= [] -> execution_failure;
                  Wrong =/= [] -> wrong_answer;
                  true -> pass
              end,
    R#{verdict => Verdict, failures => Failures, wrong => Wrong}.

%% Task 2: `BaseText' is the reply accepted in task 1, `Text' the revision.
%% The base must pass task 1 again here; the revision is checked against the
%% task 2 reference, diffed against the base byte by byte, and every input
%% whose result changed is listed.
-spec check_revision(binary(), binary()) -> {ok, revision()} | {error, {base_not_accepted, report()}}.
check_revision(BaseText, Text) ->
    check_revision(revise, BaseText, Text).

%% The same for any task that revises another, such as `reverse', whose base
%% is a `pan' reply.
-spec check_revision(wb_task:name(), binary(), binary()) ->
          {ok, revision()} | {error, {base_not_accepted, report()}}.
check_revision(Task, BaseText, Text) ->
    {ok, BaseTask} = wb_task:base(Task),
    case check(BaseTask, BaseText) of
        #{verdict := pass, bytes := BaseBytes} = Base ->
            Revised = check(Task, Text),
            Rev0 = #{base => Base, revised => Revised,
                     intended => wb_task:intended_changes(Task)},
            Rev1 = case Revised of
                       #{bytes := Bytes} -> Rev0#{hunks => wb_diff:hunks(BaseBytes, Bytes)};
                       _ -> Rev0
                   end,
            {ok, with_changes(Base, Revised, Rev1)};
        Base ->
            {error, {base_not_accepted, Base}}
    end.

with_changes(#{results := Before}, #{results := After}, Rev) when After =/= [] ->
    Changes = [{X, B, A} || {{X, B}, {X, A}} <- lists:zip(Before, After),
                            A =/= not_run, A =/= B],
    Rev#{changes => Changes};
with_changes(_Base, _Revised, Rev) ->
    Rev.
