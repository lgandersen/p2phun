-module(p2phun_peer_manager).
-include("peer.hrl").
-export([init/2]).

% Here we should do simple repeating tasks like fetching of peer information etc.
init(Count, #peerstate{my_id=MyId, peer_pid=PeerPid} = State) ->
    timer:sleep(1000),
    case Count > 1 of
        true ->
            p2phun_peer:request_peerlist(PeerPid, self()),
            receive
                {got_peerlist, Peers} -> ok
            end,
            p2phun_peertable:add_and_return_peers_not_in_table(MyId, Peers),
            NewCount = 0;
        false ->
            NewCount = Count + 1
    end,
    timer:sleep(1000),
    p2phun_peer:ping(PeerPid, self()),
    init(NewCount, State).
