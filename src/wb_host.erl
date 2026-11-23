%% What a run was done on: operating system, kernel, CPU architecture and
%% Erlang release. No host name or user name is read.
-module(wb_host).

-export([info/0, describe/1, slug/1]).

-spec info() -> map().
info() ->
    Base = #{os => os_name(),
             kernel => cmd("uname -sr"),
             arch => cmd("uname -m"),
             otp => otp_version(),
             erts => list_to_binary(erlang:system_info(version))},
    %% A run in a container or under emulation says so through this variable,
    %% set by `scripts/platform-check.sh'.
    case os:getenv("WASM_BYTES_HOST_NOTE") of
        Note when is_list(Note), Note =/= "" -> Base#{note => unicode:characters_to_binary(Note)};
        _ -> Base
    end.

-spec describe(map()) -> iodata().
describe(#{os := Os, arch := Arch, otp := Otp} = H) ->
    [Os, ", ", Arch, "; Erlang/OTP ", Otp,
     case H of
         #{note := Note} -> [" (", Note, ")"];
         _ -> []
     end].

%% `darwin-arm64', `linux-x86_64': the name of a run record.
-spec slug(map()) -> binary().
slug(#{kernel := Kernel, arch := Arch}) ->
    [Sys | _] = string:split(Kernel, " "),
    iolist_to_binary([string:lowercase(Sys), "-", Arch]).

os_name() ->
    case os:type() of
        {unix, darwin} ->
            iolist_to_binary(["macOS ", cmd("sw_vers -productVersion")]);
        {unix, linux} ->
            case file:read_file("/etc/os-release") of
                {ok, Bin} -> pretty_name(Bin);
                {error, _} -> ~"Linux"
            end;
        {Family, Name} ->
            iolist_to_binary(io_lib:format("~p/~p", [Family, Name]))
    end.

pretty_name(Bin) ->
    case [L || L <- string:split(Bin, "\n", all), string:prefix(L, "PRETTY_NAME=") =/= nomatch] of
        [Line | _] -> string:trim(string:prefix(Line, "PRETTY_NAME="), both, "\"");
        [] -> ~"Linux"
    end.

otp_version() ->
    Rel = erlang:system_info(otp_release),
    Path = filename:join([code:root_dir(), "releases", Rel, "OTP_VERSION"]),
    case file:read_file(Path) of
        {ok, V} -> string:trim(V);
        {error, _} -> list_to_binary(Rel)
    end.

cmd(C) ->
    string:trim(unicode:characters_to_binary(os:cmd(C))).
