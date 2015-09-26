-module(p2phun_peer_manager).
-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").
-export([init/2]).

% Here we should do simple repeating tasks like fetching of peer information etc.
init(Count, #peerstate{my_id=MyId, peer_pid=PeerPid} = State) ->
    timer:sleep(1000),
    case Count > -1 of
        true ->
            p2phun_peer:request_peerlist(PeerPid, self()),
            receive {got_peerlist, Peers} -> ok end,
            case Peers2Add = lists:filter(fun(#peer{id=Id} = _P) -> Id =/= MyId end, p2phun_peertable:peers_not_in_table(MyId, Peers)) of
                [] ->
                    ok;
                 _ ->
                    lager_info(MyId, "Peer-list received.")
            end,
            lists:foreach(
                fun(#peer{address=Address, server_port=Port}=_Peer) -> p2phun_peer_pool:connect(MyId, Address, Port) end,
                Peers2Add),
            NewCount = 0;
        false ->
            NewCount = Count + 1
    end,
    timer:sleep(1000),
%    p2phun_peer:request_pong(PeerPid, self()),
%    receive pong -> ok
%    after 5000 -> lager_info(MyId, "Peer not responding to pong in 5 seconds. Should be dropped.") end,
    init(NewCount, State).
