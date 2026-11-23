%% Where things are in a module's bytes.
%%
%% erlang_wasm decodes and validates a candidate, and reads an export's type,
%% through its public API. It has no public call that lists a module's imports,
%% memories or start function, so the profile check reads them here, from the
%% section headers of bytes that `wasm:compile/1' has already accepted. The byte
%% diff uses the same walk to name the section an edit falls in.
%%
%% Nothing here changes a byte.
-module(wb_layout).

-export([sections/1, find/2, count/2, exports/2, describe/2, section_name/1]).

-export_type([section/0]).

-type section() :: #{id := byte(), at := non_neg_integer(),
                     payload := non_neg_integer(), size := non_neg_integer()}.

%% The sections in order: where each starts (`at', its id byte), where its
%% contents start (`payload') and how long they are.
-spec sections(binary()) -> {ok, [section()]} | {error, non_neg_integer()}.
sections(<<0, "asm", _Version:4/binary, Rest/binary>>) ->
    walk(Rest, 8, []);
sections(_) ->
    {error, 0}.

walk(<<>>, _At, Acc) ->
    {ok, lists:reverse(Acc)};
walk(<<Id, Rest/binary>>, At, Acc) ->
    case leb_u32(Rest) of
        {ok, Size, N, Rest1} when byte_size(Rest1) >= Size ->
            <<_:Size/binary, Rest2/binary>> = Rest1,
            S = #{id => Id, at => At, payload => At + 1 + N, size => Size},
            walk(Rest2, At + 1 + N + Size, [S | Acc]);
        _ ->
            {error, At}
    end.

-spec find(byte(), [section()]) -> [section()].
find(Id, Sections) ->
    [S || #{id := I} = S <- Sections, I =:= Id].

%% The entry count at the start of a vector section, such as imports,
%% functions or memories.
-spec count(binary(), section()) -> non_neg_integer().
count(Bytes, S) ->
    {ok, N, _, _} = leb_u32(payload(Bytes, S)),
    N.

%% `[{Name, Kind, Index}]' from an export section.
-spec exports(binary(), section()) -> [{binary(), atom(), non_neg_integer()}].
exports(Bytes, S) ->
    {ok, N, _, Rest} = leb_u32(payload(Bytes, S)),
    export_entries(N, Rest).

export_entries(0, _) ->
    [];
export_entries(N, Bin) ->
    {ok, Len, _, Rest} = leb_u32(Bin),
    <<Name:Len/binary, Kind, Rest1/binary>> = Rest,
    {ok, Idx, _, Rest2} = leb_u32(Rest1),
    [{Name, export_kind(Kind), Idx} | export_entries(N - 1, Rest2)].

export_kind(0) -> func;
export_kind(1) -> table;
export_kind(2) -> memory;
export_kind(3) -> global;
export_kind(4) -> tag;
export_kind(K) -> {kind, K}.

payload(Bytes, #{payload := P, size := Size}) ->
    binary:part(Bytes, P, Size).

%% What the byte at `Offset' is part of, in words, for a module that decodes.
-spec describe(binary(), non_neg_integer()) -> iodata().
describe(Bytes, Offset) when Offset >= byte_size(Bytes) ->
    "end of module";
describe(_Bytes, Offset) when Offset < 4 ->
    "magic number";
describe(_Bytes, Offset) when Offset < 8 ->
    "version";
describe(Bytes, Offset) ->
    case sections(Bytes) of
        {ok, Sections} ->
            case [S || #{at := At, payload := P, size := Sz} = S <- Sections,
                       Offset >= At, Offset < P + Sz] of
                [S] -> in_section(Bytes, S, Offset);
                [] -> "outside any section"
            end;
        {error, _} ->
            "a module that does not decode"
    end.

in_section(_Bytes, #{id := Id, at := At}, Offset) when Offset =:= At ->
    [section_name(Id), " section id"];
in_section(_Bytes, #{id := Id, payload := P}, Offset) when Offset < P ->
    [section_name(Id), " section length"];
in_section(Bytes, #{id := 10} = S, Offset) ->
    in_code(Bytes, S, Offset);
in_section(_Bytes, #{id := Id}, _Offset) ->
    [section_name(Id), " section"].

%% The code section: which function body, and whether the byte is the body's
%% length or its contents.
in_code(Bytes, #{payload := P} = S, Offset) ->
    {ok, N, Len, Rest} = leb_u32(payload(Bytes, S)),
    case Offset < P + Len of
        true -> "code section entry count";
        false -> in_body(Rest, P + Len, 0, N, Offset)
    end.

in_body(_Rest, _At, I, N, _Offset) when I >= N ->
    "code section";
in_body(Rest, At, I, N, Offset) ->
    {ok, Size, Len, Rest1} = leb_u32(Rest),
    if
        Offset < At + Len ->
            io_lib:format("length of function body ~b", [I]);
        Offset < At + Len + Size ->
            io_lib:format("function body ~b", [I]);
        true ->
            <<_:Size/binary, Rest2/binary>> = Rest1,
            in_body(Rest2, At + Len + Size, I + 1, N, Offset)
    end.

-spec section_name(byte()) -> string().
section_name(0) -> "custom";
section_name(1) -> "type";
section_name(2) -> "import";
section_name(3) -> "function";
section_name(4) -> "table";
section_name(5) -> "memory";
section_name(6) -> "global";
section_name(7) -> "export";
section_name(8) -> "start";
section_name(9) -> "element";
section_name(10) -> "code";
section_name(11) -> "data";
section_name(12) -> "data count";
section_name(13) -> "tag";
section_name(Id) -> io_lib:format("unknown (~b)", [Id]).

%% An unsigned LEB128 of at most five bytes: `{ok, Value, BytesRead, Rest}'.
leb_u32(Bin) ->
    leb(Bin, 0, 0, 0).

leb(<<B, Rest/binary>>, Shift, Acc, N) when N < 5 ->
    V = Acc bor ((B band 16#7f) bsl Shift),
    case B band 16#80 of
        0 -> {ok, V, N + 1, Rest};
        _ -> leb(Rest, Shift + 7, V, N + 1)
    end;
leb(_, _, _, _) ->
    error.
