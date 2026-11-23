%% Test helpers: collect what a command prints, and give each test a clean
%% scratch directory.
-module(wb_test_io).

-export([capture/1, device/0, text/1, scratch/1, root/0]).

%% Runs `F' with its standard output collected: `{Result, Output}'.
capture(F) ->
    Old = group_leader(),
    Dev = device(),
    group_leader(Dev, self()),
    try F() of
        R -> {R, text(Dev)}
    after
        group_leader(Old, self())
    end.

%% An IO device that keeps everything written to it.
device() ->
    spawn(fun() -> loop([]) end).

text(Dev) ->
    Ref = make_ref(),
    Dev ! {text, self(), Ref},
    receive {Ref, T} -> T end.

loop(Acc) ->
    receive
        {io_request, From, Ref, Req} ->
            {Reply, Acc1} = request(Req, Acc),
            From ! {io_reply, Ref, Reply},
            loop(Acc1);
        {text, From, Ref} ->
            From ! {Ref, iolist_to_binary(lists:reverse(Acc))},
            loop(Acc)
    end.

request({put_chars, Enc, Chars}, Acc) ->
    {ok, [unicode:characters_to_binary(Chars, Enc) | Acc]};
request({put_chars, Enc, M, F, A}, Acc) ->
    request({put_chars, Enc, apply(M, F, A)}, Acc);
request({setopts, _}, Acc) ->
    {ok, Acc};
request(getopts, Acc) ->
    {[{binary, false}, {encoding, unicode}], Acc};
request(_, Acc) ->
    {{error, request}, Acc}.

root() ->
    {ok, Cwd} = file:get_cwd(),
    Cwd.

%% `_build/test/scratch/Name', empty.
scratch(Name) ->
    Dir = filename:join([root(), "_build", "test", "scratch", Name]),
    _ = file:del_dir_r(Dir),                 % absent the first time
    ok = filelib:ensure_path(Dir),
    Dir.
