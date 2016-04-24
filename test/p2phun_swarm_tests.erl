-module(p2phun_swarm_tests).

-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

-import(p2phun_testtools, [
     spawn_node/2,
     shutdown_nodes/1,
     create_nodes/2,
     connection/2,
     connect/2
    ]).


start_swarm(Id, NSearchers) ->
    {ok, Pid} = p2phun_swarm:start_link(Id, NSearchers),
    unlink(Pid),
    Pid.

start_link_test() ->
    Pid = start_swarm(Id = 0, NSearchers = 1),
    exit(Pid, kill).

add_peers_not_in_table_test() ->
    Pid = start_swarm(0, 1),
    ok = p2phun_swarm:add_peers_not_in_cache(0, #peer{id=1}),
    exit(Pid, kill).

next_peer_test() ->
    Pid = start_swarm(0, 1),
    ?assertEqual(no_peer_found, p2phun_swarm:next_peer(0)),
    ?assertEqual(ok, p2phun_swarm:add_peers_not_in_cache(0, [#peer{id=1}])),
    ?assertEqual(#peer{id=1}, p2phun_swarm:next_peer(0)),
    ?assertEqual(ok, p2phun_swarm:add_peers_not_in_cache(0, [#peer{id=?KEYSPACE_SIZE - 1}])),
    ?assertEqual(no_peer_found, p2phun_swarm:next_peer(0)),
    exit(Pid, kill).

adjust_nsearchers_test() ->
    NodePids = create_nodes([Id0] = [0], []),
    CheckNSearchers = fun(CheckVal) ->
        #swarm_state{nsearchers=NSearchers} = p2phun_swarm:my_state(Id0),
        ?assertEqual(NSearchers, CheckVal)
    end,
    CheckNSearchers(3),
    ok = p2phun_swarm:nsearchers(Id0, 1),
    CheckNSearchers(1),
    ok = p2phun_swarm:nsearchers(Id0, 5), CheckNSearchers(5),
    ok = p2phun_swarm:nsearchers(Id0, 5), CheckNSearchers(5),
    shutdown_nodes(NodePids).

% The final test to make! :-)
%node_lookup_test() ->
%    _NodePids = create_nodes([Id0, Id2, Id3, Id4, Id1] = [0, 2, 3, 4, 1], []),
%    connection(Id0, Id2), connection(Id2, Id3),
%    connection(Id3, Id4), connection(Id4, Id1),
%    Lol = p2phun_swarm:find_node(0, 1),
