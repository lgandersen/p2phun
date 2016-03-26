-module(p2phun_peer_tests).

-import(p2phun_testtools, [
     spawn_node/2,
     shutdown_nodes/1,
     create_nodes/2,
     connection/2,
     connect/2
    ]).

-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

handshake_test() ->
    application:ensure_started(ranch),
    NodePids = create_nodes([Id0, Id1] = [0, 1], []),
    _ChildPid = connection(Id0, Id1),
    shutdown_nodes(NodePids).

already_in_table_test() ->
    NodePids = create_nodes([Id0, Id1] = [0, 1], []),
    connection(Id0, Id1),
    ?assertMatch({error, already_in_table}, connect(Id0, Id1)),
    shutdown_nodes(NodePids).


table_full_test() ->
    NodePids = create_nodes([Id0, Id1, Id2] = [0, 1, 2], [{bigbin_nodesize, 1}]),
    ChildPid = connection(Id0, Id1),
    ?assertMatch({error, table_full}, connect(Id0, Id2)),
    shutdown_nodes(NodePids).


request_peerlist_test() ->
    NodePids = create_nodes([Id0, Id1, Id2] = [0, 1, 2], []),
    Peer0to1 = connection(Id0, Id1),
    Peer1to2 = connection(Id1, Id2),
    ExpectedPeers = sets:from_list([?PEER(Id0), ?PEER(Id2)]),
    ReceivedPeers = sets:from_list([?PEER(Id) || #peer{id=Id} <- p2phun_peer:request_peerlist(Peer0to1)]),
    ?assertEqual(ExpectedPeers, ReceivedPeers),
    ?assertMatch([], p2phun_peer:request_peerlist(Peer0to1)),
    shutdown_nodes(NodePids).

find_node_test() ->
    NodePids = create_nodes([Id0, Id1, Id32, Id33] = [0, 1, 32, 33], []),
    Peer0to1 = connection(Id0, Id1),
    Peer1to32 = connection(Id1, Id32),
    {found_node, ?PEER(32)} = p2phun_peer:find_peer(Peer0to1, 32),
    {peers_closest, [?PEER(32), ?PEER(0)]} = p2phun_peer:find_peer(Peer0to1, 33),
    Peer33to1 = connection(Id33, Id1),
    {found_node, ?PEER(33)} = p2phun_peer:find_peer(Peer0to1, 33),
    shutdown_nodes(NodePids).
