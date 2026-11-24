%% The demo's module profile, checked before anything is instantiated.
%%
%% A candidate must define exactly one function, export it under the task's
%% name with the task's signature, export nothing else, and have no imports,
%% no memory and no start function. Tables, globals and data are not part of
%% the profile; a candidate that has them is still checked by its answers.
-module(wb_profile).

-export([check/2, check_open/3, format_violation/1, signature/1]).

-export_type([violation/0]).

-type violation() :: {imports, pos_integer()}
                   | {memories, pos_integer()}
                   | start_function
                   | {defined_functions, non_neg_integer()}
                   | {missing_export, binary()}
                   | {export_not_a_function, binary(), atom()}
                   | {signature, binary(), Want :: tuple(), Got :: tuple()}
                   | {signature_unreadable, binary(), term()}
                   | {unexpected_exports, [binary()]}.

%% `Bytes' must be a module `wasm:compile/1' accepted.
-spec check(binary(), wb_task:name()) -> ok | {error, [violation()]}.
check(Bytes, TaskName) ->
    #{export := Export, params := Params, results := Results} = wb_task:get(TaskName),
    {ok, Sections} = wb_layout:sections(Bytes),
    Count = fun(Id) ->
                lists:sum([wb_layout:count(Bytes, S) || S <- wb_layout:find(Id, Sections)])
            end,
    Imports = Count(2),
    Funcs = Count(3),
    Mems = Count(5),
    Exports = lists:append([wb_layout:exports(Bytes, S) || S <- wb_layout:find(7, Sections)]),
    Violations =
        [{imports, Imports} || Imports > 0]
        ++ [{memories, Mems} || Mems > 0]
        ++ [start_function || wb_layout:find(8, Sections) =/= []]
        ++ [{defined_functions, Funcs} || Funcs =/= 1]
        ++ export_violations(Bytes, Exports, Export, {Params, Results}),
    case Violations of
        [] -> ok;
        _ -> {error, Violations}
    end.

%% The open profile, for a write case: the module must export `Export' with
%% the signature `Want' and import nothing, since nothing is provided. It may
%% define other functions, a memory, or a start function; the calls decide.
-spec check_open(binary(), binary(), {[atom()], [atom()]}) -> ok | {error, [violation()]}.
check_open(Bytes, Export, Want) ->
    {ok, Sections} = wb_layout:sections(Bytes),
    Imports = lists:sum([wb_layout:count(Bytes, S) || S <- wb_layout:find(2, Sections)]),
    Exports = lists:append([wb_layout:exports(Bytes, S) || S <- wb_layout:find(7, Sections)]),
    Named = [V || V <- export_violations(Bytes, Exports, Export, Want),
                  element(1, V) =/= unexpected_exports],
    case [{imports, Imports} || Imports > 0] ++ Named of
        [] -> ok;
        Violations -> {error, Violations}
    end.

export_violations(Bytes, Exports, Export, Want) ->
    Named = case lists:keyfind(Export, 1, Exports) of
                false ->
                    [{missing_export, Export}];
                {_, func, _} ->
                    %% The type comes from erlang_wasm's public API.
                    case wasm:func_type_of(Bytes, Export) of
                        {ok, Want} -> [];
                        {ok, Got} -> [{signature, Export, Want, Got}];
                        {error, Why} -> [{signature_unreadable, Export, Why}]
                    end;
                {_, Kind, _} ->
                    [{export_not_a_function, Export, Kind}]
            end,
    Others = [Name || {Name, _, _} <- Exports, Name =/= Export],
    Named ++ [{unexpected_exports, Others} || Others =/= []].

-spec format_violation(violation()) -> iodata().
format_violation({imports, N}) ->
    io_lib:format("imports ~b item~s; the profile allows no imports", [N, plural(N)]);
format_violation({memories, N}) ->
    io_lib:format("defines ~b memor~s; the profile allows no memory",
                  [N, case N of 1 -> "y"; _ -> "ies" end]);
format_violation(start_function) ->
    "has a start function; the profile allows none";
format_violation({defined_functions, N}) ->
    io_lib:format("defines ~b function~s; the profile wants exactly one", [N, plural(N)]);
format_violation({missing_export, Name}) ->
    io_lib:format("does not export \"~ts\"", [Name]);
format_violation({export_not_a_function, Name, Kind}) ->
    io_lib:format("exports \"~ts\" as a ~p, not a function", [Name, Kind]);
format_violation({signature, Name, Want, Got}) ->
    io_lib:format("\"~ts\" has type ~ts; the task wants ~ts",
                  [Name, signature(Got), signature(Want)]);
format_violation({signature_unreadable, Name, Why}) ->
    io_lib:format("the type of \"~ts\" cannot be read: ~0p", [Name, Why]);
format_violation({unexpected_exports, Names}) ->
    io_lib:format("also exports ~ts; the profile allows one export",
                  [lists:join(", ", [["\"", N, "\""] || N <- Names])]).

-spec signature({[atom()], [atom()]}) -> iodata().
signature({Params, Results}) ->
    ["(", lists:join(", ", [atom_to_list(P) || P <- Params]), ") -> (",
     lists:join(", ", [atom_to_list(R) || R <- Results]), ")"].

plural(1) -> "";
plural(_) -> "s".
