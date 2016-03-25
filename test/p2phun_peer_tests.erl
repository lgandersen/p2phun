-module(p2phun_peer_tests).

-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(NODE(Id), #node_config{id=Id, address={?LOCALHOST, 5000 + Id}}).
-define(LOCALHOST, {10,0,2,6}).
-define(PEER(Id), #peer{id=Id, address=?LOCALHOST, server_port=5000 + Id}).

spawn_node(Id, RoutingTableUpdates) ->
    RoutingTableSpec = [{space_size, 64}, {number_of_smallbins, 2}, {bigbin_nodesize, 2}, {smallbin_nodesize, 3}, {bigbin_spacesize, 32}],
    ReplaceOption = fun ({Name, _} = Opt, RTSpec) -> lists:keyreplace(Name, 1, RTSpec, Opt) end,
    RoutingTableSpec1 = lists:foldl(ReplaceOption, RoutingTableSpec, RoutingTableUpdates),
    {ok, Pid} = p2phun_node_sup:start_link_no_manager(?NODE(Id), maps:from_list(RoutingTableSpec1)),
    Pid.

shutdown_nodes(NodePids) ->
    lists:foreach(fun shutdown_node/1, NodePids).

shutdown_node(NodePid) ->
    Ref = monitor(process, NodePid),
    unlink(NodePid),
    exit(NodePid, shutdown),
    receive
        {'DOWN', Ref, process, NodePid, _Reason} -> ok
    after 5000 ->
        error(exit_timeout)
    end.

create_nodes(Ids, RoutingTableUpdates) ->
    lists:map(fun(Id) -> spawn_node(Id, RoutingTableUpdates) end, Ids).

connection(IdClient, IdServer) ->
    {connected, ChildPid} = p2phun_peer_pool:connect_sync(IdClient, ?LOCALHOST, 5000 + IdServer),
    ChildPid.

connect(IdClient, IdServer) ->
    p2phun_peer_pool:connect_sync(IdClient, ?LOCALHOST, 5000 + IdServer).

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
