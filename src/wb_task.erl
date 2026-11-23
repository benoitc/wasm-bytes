%% The two tasks, their reference predicates and the inputs every candidate is
%% called with.
%%
%% The references are written from the English specifications, in Erlang,
%% without looking at any candidate. They are the only definition of a right
%% answer in this repository.
-module(wb_task).

-export([get/1, names/0, inputs/0, expected/2, intended_changes/0]).

-export_type([name/0, task/0]).

-define(MIN_I32, -2147483648).
-define(MAX_I32, 2147483647).

-type name() :: write | revise.
-type task() :: #{name := name(),
                  export := binary(),
                  params := [atom()],
                  results := [atom()],
                  prompt := file:filename()}.

-spec names() -> [name()].
names() -> [write, revise].

-spec get(name()) -> task().
get(write) ->
    #{name => write, export => ~"retry", params => [i32], results => [i32],
      prompt => "prompts/write.txt"};
get(revise) ->
    #{name => revise, export => ~"retry", params => [i32], results => [i32],
      prompt => "prompts/revise.txt"}.

-spec expected(name(), integer()) -> 0 | 1.
expected(write, X) -> write_reference(X);
expected(revise, X) -> revise_reference(X).

%% Task 1: 1 for 429, 1 for 500 through 599 inclusive, 0 for every other i32.
write_reference(429) -> 1;
write_reference(X) when X >= 500, X =< 599 -> 1;
write_reference(_) -> 0.

%% Task 2: task 1, and also 1 for 408, and 0 for 501. Written out again rather
%% than derived from `write_reference/1', so that a mistake in one does not
%% carry into the other.
revise_reference(408) -> 1;
revise_reference(429) -> 1;
revise_reference(501) -> 0;
revise_reference(X) when X >= 500, X =< 599 -> 1;
revise_reference(_) -> 0.

%% Every status from 100 through 599, then the values outside that range that
%% catch the usual ways a hand-written range check goes wrong.
-spec inputs() -> [integer()].
inputs() ->
    lists:usort(lists:seq(100, 599) ++ out_of_range()).

out_of_range() ->
    %% The i32 boundaries.
    [?MIN_I32, ?MIN_I32 + 1, -1, 0, 1, ?MAX_I32 - 1, ?MAX_I32]
    %% Just outside the statuses.
    ++ [99, 600, 601, 999, 1000]
    %% Negatives of the values that matter: a signed comparison where an
    %% unsigned one was meant, or the other way round, shows up here.
    ++ [-408, -429, -500, -501, -599, -600]
    %% Values whose low 16 bits, or low 31 bits, are a value that matters:
    %% a check on a truncated or sign-stripped argument answers 1 for them.
    ++ [X + 65536 || X <- [408, 429, 500, 501, 599]]
    ++ [X - 65536 || X <- [429, 500]]
    ++ [?MIN_I32 + X || X <- [429, 500, 599]].

%% The inputs whose result the change request in task 2 changes, as
%% `{Input, Before, After}', computed from the two references.
-spec intended_changes() -> [{integer(), 0 | 1, 0 | 1}].
intended_changes() ->
    [{X, write_reference(X), revise_reference(X)}
     || X <- inputs(), write_reference(X) =/= revise_reference(X)].
