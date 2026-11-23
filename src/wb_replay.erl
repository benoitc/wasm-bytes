%% The short replay: one recorded model reply traced to its bytes, then five
%% replies run through erlang_wasm and the checker, each with the check that
%% decided its outcome.
%%
%% Four of the five are constructed examples, labelled as such. Each shows a
%% different protection at work. The fifth is the recorded model reply.
-module(wb_replay).

-export([run/1, cases/0]).

-define(TRIAL, "trials/write/claude-sonnet-5-5-1").

%% `{Kind, Directory, Expected verdict}'.
-spec cases() -> [{constructed | model_trial, string(), wb_check:verdict()}].
cases() ->
    [{constructed, "examples/write/stack-mismatch", invalid},
     {constructed, "examples/write/has-memory", interface_mismatch},
     {constructed, "examples/write/loops-on-negative", execution_failure},
     {constructed, "examples/write/misses-599", wrong_answer},
     {model_trial, ?TRIAL, pass}].

%% Prints the replay; `{Output, AllAsExpected}'.
-spec run(file:filename()) -> {iodata(), boolean()}.
run(Root) ->
    {ok, T} = wb_trace:load(filename:join(Root, ?TRIAL)),
    #{config := C, decoded := {ok, Bytes}, recorded := Recorded} = T,
    Hash = wb_trace:sha256(Bytes),
    Rows = [{K, D, Want, wb_check:check(write, reply(Root, D))} || {K, D, Want} <- cases()],
    Ok = Recorded =:= Hash andalso lists:all(fun({_, _, W, #{verdict := V}}) -> W =:= V end, Rows),
    Out = [io_lib:format("wasm-bytes replay: erlang_wasm ~ts on ~ts~n~n",
                         [vsn(), wb_host:describe(wb_host:info())]),
           io_lib:format("1. A model wrote these bytes: ~ts, recorded ~ts~n",
                         [maps:get(model, C), maps:get(recorded_on, C)]),
           field("prompt", [?TRIAL, "/prompt.txt"]),
           field("reply", [?TRIAL, "/reply.txt, unedited"]),
           field("module", io_lib:format("~b bytes decoded from the hex", [byte_size(Bytes)])),
           field("sha256", [Hash, case Recorded of
                                      Hash -> ", as recorded in module.sha256";
                                      _ -> ", NOT the hash in module.sha256"
                                  end]),
           "\n2. What erlang_wasm and the checker did with five replies\n",
           [outcome(K, D, R) || {K, D, _, R} <- Rows],
           "\nSee every byte: bin/wasm-bytes trace ", ?TRIAL, "\n",
           "Run it in Wasmtime too: bin/wasm-bytes compare write ", ?TRIAL, "/reply.txt\n"],
    {Out, Ok}.

reply(Root, Dir) ->
    {ok, Bin} = file:read_file(filename:join([Root, Dir, "reply.txt"])),
    Bin.

outcome(Kind, Dir, #{verdict := V} = R) ->
    Tag = case Kind of
              constructed -> "constructed";
              model_trial -> "model trial"
          end,
    [First | More] = why(R),
    [io_lib:format("  [~ts] ~ts~n", [Tag, Dir]),
     io_lib:format("      ~-19s ~ts~n", [atom_to_list(V), First]),
     [io_lib:format("      ~-19s ~ts~n", ["", L]) || L <- More]].

%% Which check decided the outcome, and what it saw: one or more lines.
why(#{verdict := invalid, why := #{msg := Msg}}) ->
    [["erlang_wasm's validator refused the module before anything ran: ", Msg]];
why(#{verdict := interface_mismatch, why := Violations}) ->
    ["erlang_wasm validated it; the checker's interface rules refused it before it was"
     " instantiated:"
     | [["- it ", wb_profile:format_violation(V)] || V <- Violations]];
why(#{verdict := execution_failure, failures := Failures, results := Results}) ->
    Fuel = length([F || {_, #{kind := out_of_fuel}} = F <- Failures]),
    [io_lib:format("erlang_wasm's fuel budget stopped ~b call~s; the other ~b calls returned",
                   [Fuel, plural(Fuel), length(Results) - length(Failures)])];
why(#{verdict := wrong_answer, wrong := Wrong}) ->
    [["erlang_wasm ran every call within its limits; the reference check found ",
      lists:join(", ", [io_lib:format("input ~b expected ~b, got ~b", [X, Want, Got])
                        || {X, Want, Got} <- lists:sublist(Wrong, 3)]),
      case length(Wrong) > 3 of
          true -> io_lib:format(" and ~b more", [length(Wrong) - 3]);
          false -> []
      end]];
why(#{verdict := pass, results := Results}) ->
    [io_lib:format("validated, accepted by the interface rules, ran within its limits;"
                   " ~b of ~b answers match the reference", [length(Results), length(Results)])];
why(#{verdict := V}) ->
    [io_lib:format("stopped at ~p", [V])].

field(Tag, Text) ->
    [io_lib:format("  ~-8s ", [Tag]), Text, $\n].

plural(1) -> "";
plural(_) -> "s".

vsn() ->
    case application:get_key(wasm, vsn) of
        {ok, V} -> V;
        undefined -> "?"
    end.
