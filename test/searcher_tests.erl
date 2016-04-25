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


%% API Function tests

start_link_test() ->
    {ok, Pid} = p2phun_searcher:start_link(Id0 = 0, not_really_a_cache_table).

find_node_in_cache_test() ->
    [Id0, Id1] = [0, 1],
    _NodePids = create_nodes([Id0, Id1], []),
    #swarm_state{cache=Cache, searchers=[SearcherPid|_Rest]} = p2phun_swarm:my_state(Id0),
    p2phun_swarm:add_peers_not_in_cache(0, [?PEER(Id1)]),
    ?assertEqual(ok, p2phun_searcher:find(SearcherPid, {find_node, Id1})),
    receive
        Msg -> ?assertMatch(#search_findings{searcher=Pid, type=node_found, data=PeerPid}, Msg)
    end.
