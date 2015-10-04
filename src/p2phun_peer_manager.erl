-module(p2phun_peer_manager).
-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").
-export([init/3]).

% Here we should do simple repeating tasks like fetching of peer information etc.
init(Count, MyId, PeerPid) ->
    timer:sleep(1000),
    case Count > 0 of
        true ->
            Peers = p2phun_peer:request_peerlist(PeerPid),
            Peers2Add = lists:filter(fun(#peer{id=Id} = _P) -> Id =/= MyId end, p2phun_peertable:peers_not_in_table(MyId, Peers)),
            lists:foreach(
                fun(#peer{address=Address, server_port=Port}=_Peer) -> p2phun_peer_pool:connect(MyId, Address, Port) end,
                Peers2Add),
            NewCount = 0;
        false ->
            NewCount = Count + 1
    end,
    timer:sleep(1000),
    case p2phun_peer:ping(PeerPid) of
        ping_timeout ->
            % Perhaps take some action?
            lager_info(MyId, "Peer not responding to pong in 5 seconds. Should be dropped.");
        ok -> ok
    end,
    init(NewCount, MyId, PeerPid).
