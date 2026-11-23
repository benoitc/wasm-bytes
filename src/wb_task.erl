%% The tasks, their reference functions and the inputs each candidate is
%% called with.
%%
%%   write   retry(x): 1 for 429 and for 500 through 599, 0 otherwise
%%   revise  retry(x) changed: 408 becomes 1, 501 becomes 0
%%   digits  digit_sum(x): the sum of the decimal digits of x, or of -x when
%%           x is negative; a loop, locals and unsigned division
%%
%% The references are written from the English specifications, in Erlang,
%% without looking at any candidate. They are the only definition of a right
%% answer in this repository.
-module(wb_task).

-export([get/1, names/0, inputs/1, expected/2, intended_changes/0, prompt/2]).

-export_type([name/0, task/0]).

-define(MIN_I32, -2147483648).
-define(MAX_I32, 2147483647).

-type name() :: write | revise | digits.
-type task() :: #{name := name(),
                  export := binary(),
                  params := [atom()],
                  results := [atom()],
                  prompt := file:filename()}.

-spec names() -> [name()].
names() -> [write, revise, digits].

-spec get(name()) -> task().
get(write) ->
    #{name => write, export => ~"retry", params => [i32], results => [i32],
      prompt => "prompts/write.txt", guided => "prompts/write.guided.txt"};
get(revise) ->
    #{name => revise, export => ~"retry", params => [i32], results => [i32],
      prompt => "prompts/revise.txt"};
get(digits) ->
    #{name => digits, export => ~"digit_sum", params => [i32], results => [i32],
      prompt => "prompts/digits.txt", guided => "prompts/digits.guided.txt"}.

%% The prompt file for a task. `baseline' states the task and the reply
%% format. `guided' adds a reference card (module layout, LEB128, the byte of
%% each instruction with its operands) and numbered steps; only the tasks
%% with one prompt have it.
-spec prompt(name(), baseline | guided) -> {ok, file:filename()} | {error, no_guided_prompt}.
prompt(Task, baseline) ->
    #{prompt := P} = wb_task:get(Task),
    {ok, P};
prompt(Task, guided) ->
    case wb_task:get(Task) of
        #{guided := P} -> {ok, P};
        _ -> {error, no_guided_prompt}
    end.

-spec expected(name(), integer()) -> non_neg_integer().
expected(write, X) -> write_reference(X);
expected(revise, X) -> revise_reference(X);
expected(digits, X) -> digits_reference(X).

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

%% The digits of |x| in Erlang's own integers, which have no 32-bit limit, so
%% -2147483648 gives the digits of 2147483648.
digits_reference(X) ->
    lists:sum([D - $0 || D <- integer_to_list(abs(X))]).

-spec inputs(name()) -> [integer()].
inputs(write) -> retry_inputs();
inputs(revise) -> retry_inputs();
inputs(digits) -> digit_inputs().

%% Every status from 100 through 599, then the values outside that range that
%% catch the usual ways a hand-written range check goes wrong.
retry_inputs() ->
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

%% Every number from 0 through 1000 and from -1 through -100, each power of
%% ten and its neighbours with both signs, the i32 boundaries, numbers made of
%% one repeated digit, and 200 numbers spread over the whole i32 range.
digit_inputs() ->
    Powers = [pow10(K) || K <- lists:seq(1, 9)],
    lists:usort(lists:seq(0, 1000) ++ lists:seq(-100, -1)
                ++ lists:append([[P - 1, P, P + 1, 1 - P, -P, -P - 1] || P <- Powers])
                ++ [?MIN_I32, ?MIN_I32 + 1, ?MAX_I32 - 1, ?MAX_I32]
                ++ [999999999, 1999999999, 1111111111, -1111111111, 1234567890,
                    -1234567890, 2000000000, -2000000000]
                ++ spread(200)).

pow10(0) -> 1;
pow10(K) -> 10 * pow10(K - 1).

%% A fixed linear congruential sequence, written out so that the inputs are
%% the same on every Erlang release, read as signed 32-bit integers.
spread(N) ->
    spread(N, 2026, []).

spread(0, _X, Acc) ->
    lists:reverse(Acc);
spread(N, X, Acc) ->
    Next = (1103515245 * X + 12345) band 16#FFFFFFFF,
    Signed = case Next > ?MAX_I32 of
                 true -> Next - 16#100000000;
                 false -> Next
             end,
    spread(N - 1, Next, [Signed | Acc]).

%% The inputs whose result the change request in task 2 changes, as
%% `{Input, Before, After}', computed from the two references.
-spec intended_changes() -> [{integer(), 0 | 1, 0 | 1}].
intended_changes() ->
    [{X, write_reference(X), revise_reference(X)}
     || X <- inputs(revise), write_reference(X) =/= revise_reference(X)].
