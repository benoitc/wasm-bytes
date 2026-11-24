%% Writes the reference modules the reading tasks show a model.
%%
%% A reading case built from the spec tests needs the bytes of a module that
%% does one thing: apply one i32 instruction to its arguments. That module is
%% small enough to write out here, byte by byte, rather than through an
%% assembler. Only the runner writes these bytes; in a writing task, the
%% model writes every byte.
-module(wb_encode).

-export([op_module/2, uleb/1]).

%% A module with one function, exported as `f', of type
%% `(i32{Arity}) -> (i32)': `local.get' for each argument, then `Opcode',
%% then `end'. No imports, memory, start function or custom section.
-spec op_module(1 | 2, byte()) -> binary().
op_module(Arity, Opcode) when Arity =:= 1; Arity =:= 2 ->
    Params = binary:copy(<<16#7f>>, Arity),
    FuncType = <<16#60, Arity, Params/binary, 1, 16#7f>>,
    Gets = << <<16#20, I>> || I <- lists:seq(0, Arity - 1) >>,
    Body = <<0, Gets/binary, Opcode, 16#0b>>,
    <<0, "asm", 1, 0, 0, 0,
      (section(1, <<1, FuncType/binary>>))/binary,
      (section(3, <<1, 0>>))/binary,
      (section(7, <<1, 1, "f", 0, 0>>))/binary,
      (section(10, <<1, (uleb(byte_size(Body)))/binary, Body/binary>>))/binary>>.

section(Id, Content) ->
    <<Id, (uleb(byte_size(Content)))/binary, Content/binary>>.

%% Unsigned LEB128, as every length in a module is written.
-spec uleb(non_neg_integer()) -> binary().
uleb(N) when N < 128 -> <<N>>;
uleb(N) -> <<(128 bor (N band 127)), (uleb(N bsr 7))/binary>>.
