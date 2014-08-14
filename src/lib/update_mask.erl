-module(update_mask).

-export([set_bits/3, set_bit/2, get_bit/2]).
-export([empty/1]).

-include("include/binary.hrl").


set_bit(Field, Mask) when is_atom(Field) ->
	Index = update_fields:fields(Field),
	set_bit(Index, Mask);
set_bit(Index, Mask) ->
	set_bit(Index, 1, Mask).

set_bit(Index, Bit, Mask) ->
	MaskIndex = Index bsr 3,
	LowIndex = Index band 16#7,
	BitValue = Bit bsl LowIndex,
	ByteSize = MaskIndex,
	<<Head:ByteSize/binary, OldValue?B, Tail/binary>> = Mask,
	NewValue = OldValue bor BitValue,
	<<Head/binary, NewValue?B, Tail/binary>>.

set_bits(Count, EmptyMask, Values) ->
	lists:foldl(fun(Index, Mask) ->
		Value = object_values:get_value(Index, Values),
		Bit = if Value > 0 -> 1;
			true -> 0
		end,
		set_bit(Index, Bit, Mask)
	end, EmptyMask, lists:seq(0, Count)).


get_bit(Mask, Index) ->
			MaskIndex = Index bsr 3,
			LowIndex = Index band 16#7,
			Value = 1 bsl LowIndex,
			ByteSize = MaskIndex,
			<<_Head:ByteSize/binary, OldValue?B, _Tail/binary>> = Mask,
			NewValue = OldValue band Value,
			NewValue > 0.


empty(Type) when is_atom(Type) ->
	TotalCount = update_fields:get_total_count(Type),
	update_mask:empty(TotalCount - 1);
empty(Count) ->
	Blocks = (Count + 31) div 32,
	binary:copy(<<0?L>>, Blocks).
