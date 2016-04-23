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

-record(state, {my_id, cache, id2find, searchers, nsearchers, responses, caller_pid}).

%% API Function tests

start_link_test() ->
    p2phun_searcher:start_link(Id0 = 0, not_really_a_cache_table).

find_test_node_in_cache() ->
    _NodePids = create_nodes([Id1] = [1], []),
    p2phun_swarm:start_link(Id0 = 0, 1),
    Cache = p2phun_swarm:get_cache(Id0),
    {ok, SearcherPid} = p2phun_searcher:start_link(Id0 = 0, Cache),
    p2phun_swarm:add_peers_not_in_cache(0, [#peer{id=1}]),
    ?assertEqual(ok, p2phun_searcher:find(SearcherPid, {find_node, 1})).
    %TODO this should be extended: receive the message from the searcher which will be sent back
