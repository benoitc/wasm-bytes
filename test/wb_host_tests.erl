-module(wb_host_tests).

-include_lib("eunit/include/eunit.hrl").

pretty_name_test() ->
    Release = <<"PRETTY_NAME=\"Debian GNU/Linux 13 (trixie)\"\nNAME=\"Debian GNU/Linux\"\n">>,
    ?assertEqual(~"Debian GNU/Linux 13 (trixie)", wb_host:pretty_name(Release)),
    ?assertEqual(~"Linux", wb_host:pretty_name(~"NAME=Something\n")).

slug_test() ->
    ?assertEqual(~"darwin-arm64", wb_host:slug(#{kernel => ~"Darwin 27.2.0", arch => ~"arm64"})),
    ?assertEqual(~"linux-x86_64",
                 wb_host:slug(#{kernel => ~"Linux 7.2.12-orbstack", arch => ~"x86_64"})).

describe_test() ->
    H = #{os => ~"macOS 27.2", arch => ~"arm64", otp => ~"29.1.2"},
    ?assertEqual(~"macOS 27.2, arm64; Erlang/OTP 29.1.2", iolist_to_binary(wb_host:describe(H))),
    ?assertEqual(~"macOS 27.2, arm64; Erlang/OTP 29.1.2 (in a VM)",
                 iolist_to_binary(wb_host:describe(H#{note => ~"in a VM"}))).

%% The note comes from the environment, and only when it is set.
info_note_test() ->
    Old = os:getenv("WASM_BYTES_HOST_NOTE"),
    try
        os:unsetenv("WASM_BYTES_HOST_NOTE"),
        Plain = wb_host:info(),
        ?assertNot(is_map_key(note, Plain)),
        [?assert(is_binary(maps:get(K, Plain))) || K <- [os, kernel, arch, otp, erts]],
        os:putenv("WASM_BYTES_HOST_NOTE", "Linux container"),
        ?assertMatch(#{note := ~"Linux container"}, wb_host:info())
    after
        case Old of
            false -> os:unsetenv("WASM_BYTES_HOST_NOTE");
            _ -> os:putenv("WASM_BYTES_HOST_NOTE", Old)
        end
    end.
