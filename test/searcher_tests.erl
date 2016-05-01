-module(searcher_tests).

-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

-import(p2phun_testtools, [
     spawn_node/2,
     shutdown_nodes/1,
     create_nodes/2,
     connection/2,
     connect/2
    ]).


start_link_test() ->
    {ok, Pid} = p2phun_searcher:start_link(Id0 = 0, not_really_a_cache_table).

find_node_in_cache_test() ->
    [Id0, Id1] = [0, 1],
    NodePids = create_nodes([Id0, Id1], []),
    SearcherPid = get_searcher(Id0),
    p2phun_swarm:add_peers_not_in_cache(Id0, [?PEER(Id1)]),
    Msg = do_lookup_and_receive_result(SearcherPid, Id1),
    ?assertMatch(#search_findings{searcher=_Pid, type=node_found, data=PeerPid}, Msg),
    shutdown_nodes(NodePids).

find_node_through_node_in_cache_not_connected_to_test() ->
    [Id0, Id1, Id2] = [0, 1, 2],
    NodePids = create_nodes([Id0, Id1, Id2], []),
    connection(Id1, Id2),
    p2phun_swarm:add_peers_not_in_cache(Id0, [?PEER(Id1)]),
    SearcherPid = get_searcher(Id0),
    Msg = do_lookup_and_receive_result(SearcherPid, Id1),
    ?assertMatch(#search_findings{searcher=_Pid, type=node_found, data=PeerPid}, Msg),
    shutdown_nodes(NodePids).

find_node_through_node_in_cache_connected_to_test() ->
    [Id0, Id1, Id2] = [0, 1, 2],
    NodePids = create_nodes([Id0, Id1, Id2], []),
    connection(Id1, Id2),
    PeerPid = connection(Id0, Id1),
    SearcherPid = get_searcher(Id0),
    p2phun_swarm:add_peers_not_in_cache(Id0, [?PEER(Id1)#peer{pid=PeerPid}]),
    Msg = do_lookup_and_receive_result(SearcherPid, Id1),
    ?assertMatch(#search_findings{searcher=_Pid, type=node_found, data=PeerPid}, Msg),
    shutdown_nodes(NodePids).

find_node_through_node_through_node_in_cache_test() ->
    [Id50, Id0, Id1, Id2] = [50, 0, 1, 2],
    NodePids = create_nodes([Id50, Id0, Id1, Id2], []),
    connection(Id2, Id1),
    connection(Id1, Id0),
    SearcherPid = get_searcher(Id50),
    p2phun_swarm:add_peers_not_in_cache(Id50, [?PEER(Id2)]),
    Msg1 = do_lookup_and_receive_result(SearcherPid, Id0),
    ?assertMatch(#search_findings{searcher=SearcherPid, type=nodes_closer, data=Peers}, Msg1),
    ?assertMatch([#peer{id=Id1}, #peer{id=Id50}], Msg1#search_findings.data), % It is not part of the spec that they preserve order.
    receive % Since the searcher tries to find the next peer to connect to, it will come up with an error saying no more peers left.
        Msg2 -> ?assertMatch(#search_findings{searcher=SearcherPid, type=no_more_peers_in_cache, data=no_data}, Msg2)
    end,
    p2phun_swarm:add_peers_not_in_cache(Id50, [?PEER(Id1)]),
    Msg3 = do_lookup_and_receive_result(SearcherPid, Id0),
    ?assertMatch(#search_findings{searcher=SearcherPid, type=node_found, data=_PeerPid}, Msg3),
    shutdown_nodes(NodePids).

get_searcher(Id) ->
    p2phun_swarm:nsearchers(Id, 1),
    #swarm_state{searchers=[SearcherPid]} = p2phun_swarm:my_state(Id),
    SearcherPid.

do_lookup_and_receive_result(SearcherPid, Id) ->
    ?assertEqual(ok, p2phun_searcher:find(SearcherPid, {find_node, Id})),
    receive Msg -> Msg end.
