-module(p2phun_utils).

-export([id2proc_name/2, peer_process_name/2]).

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
