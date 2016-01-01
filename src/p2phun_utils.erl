-module(p2phun_utils).
-include("peer.hrl").

-export([
    id2proc_name/2,
    peer_process_name/2,
    lager_info/3,
    lager_info/2,
    floor/1,
    ceiling/1,
    b64/1,
    bin/1,
    int/2
    ]).

-spec id2proc_name(BaseName :: atom(), Id :: integer() | binary()) -> atom().
id2proc_name(BaseName, Id) when is_atom(BaseName), is_integer(Id) -> 
    id2proc_name(BaseName, integer_to_binary(Id));
id2proc_name(BaseName, Id) when is_atom(BaseName), is_binary(Id) -> 
    BaseNameBin = atom_to_binary(BaseName, latin1),
    binary_to_atom(<<BaseNameBin/binary, Id/binary>>, latin1).

peer_process_name(MyId, PeerId) ->
    MyIdBin = integer_to_binary(MyId),
    PeerIdBin = integer_to_binary(PeerId),   
    ProcessName = <<<<"peer_myid">>/binary, MyIdBin/binary, <<"_peerid">>/binary, PeerIdBin/binary>>,
    binary_to_atom(ProcessName, 'utf8').

lager_info(Id, Msg) ->
    lager_info(Id, Msg, []).
lager_info(Id, Msg, Param) ->
    lager:info("~p: " ++ Msg, [b64(Id)] ++ Param).

% using big endian
b64(Id_Int) when is_integer(Id_Int) ->
    b64(binary:encode_unsigned(Id_Int));
b64(Id_Bin) when is_binary(Id_Bin) ->
    base64:encode(Id_Bin);
b64(undefined) ->
    undefined.

bin(Id_Int) when is_integer(Id_Int) ->
    binary:encode_unsigned(Id_Int);
bin(Id_b64) when is_binary(Id_b64) ->
    base64:decode(Id_b64).

int(b64, Id_b64) ->
    int(bin, base64:decode(Id_b64));
int(bin, Id_Bin) ->
    binary:decode_unsigned(Id_Bin).

floor(X) when X < 0 ->
    T = trunc(X),
    case X - T == 0 of
        true -> T;
        false -> T - 1
    end;
floor(X) -> 
    trunc(X).

ceiling(X) when X < 0 ->
    trunc(X);
ceiling(X) ->
    T = trunc(X),
    case X - T == 0 of
        true -> T;
        false -> T + 1
    end.
