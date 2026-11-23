%% A few lines of binary encoder, so the tests can build modules that break
%% one rule of the profile at a time. The runner itself never encodes a module.
-module(wb_test_wasm).

-export([module/1, retry_body/0, func_type/2]).

%% `Parts' maps a section name to its entries, already encoded.
module(Parts) ->
    Order = [{type, 1}, {import, 2}, {function, 3}, {memory, 5}, {global, 6},
             {export, 7}, {start, 8}, {code, 10}],
    Sections = [section(Id, maps:get(Name, Parts))
                || {Name, Id} <- Order, is_map_key(Name, Parts)],
    iolist_to_binary([<<0, "asm", 1, 0, 0, 0>> | Sections]).

section(8, FuncIdx) ->
    sized(8, leb(FuncIdx));
section(Id, Entries) when is_list(Entries) ->
    sized(Id, [leb(length(Entries)) | Entries]).

sized(Id, Payload) ->
    Bin = iolist_to_binary(Payload),
    [Id, leb(byte_size(Bin)), Bin].

func_type(Params, Results) ->
    [16#60, leb(length(Params)), [valtype(P) || P <- Params],
     leb(length(Results)), [valtype(R) || R <- Results]].

valtype(i32) -> 16#7f;
valtype(i64) -> 16#7e.

%% The instructions of write/accepted, as a code section entry.
retry_body() ->
    Body = <<0, 16#20, 0, 16#41, 16#ad, 16#03, 16#46, 16#20, 0, 16#41, 16#f4, 16#03,
             16#6b, 16#41, 16#e4, 0, 16#49, 16#72, 16#0b>>,
    [leb(byte_size(Body)), Body].

leb(N) when N < 128 -> <<N>>;
leb(N) -> <<(N band 16#7f bor 16#80), (leb(N bsr 7))/binary>>.
