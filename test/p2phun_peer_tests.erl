-module(p2phun_peer_tests).

-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

spawn_node(Node) ->
    RoutingTableSpec = [{space_size, 64}, {number_of_smallbins, 3}, {bigbin_nodesize, 8}, {smallbin_nodesize, 3}, {bigbin_spacesize, 32}],
    p2phun_node_sup:start_link_no_manager(Node, maps:from_list(RoutingTableSpec)).

handshake_test() ->
    application:ensure_started(ranch),
    {Id0, Id1} = {0, 1},
    Node0 = #node_config{id=Id0, address={"127.0.0.1", 5000}},
    Node1 = #node_config{id=Id1, address={"127.0.0.1", 5001}},
    NodePid0 = spawn_node(Node0),
    NodePid1 = spawn_node(Node1),
    {connected, ChildPid} = p2phun_peer_pool:connect_sync(Id0, "127.0.0.1", 5001),
    {error, already_in_table} = p2phun_peer_pool:connect_sync(Id1, "127.0.0.1", 5000).
