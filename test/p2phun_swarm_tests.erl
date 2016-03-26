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

-record(state, {my_id, cache, id2find, searchers, nsearchers, responses, caller_pid}).

adjust_nsearchers_test() ->
    NodePids = create_nodes([Id0] = [0], []),
    CheckNSearchers = fun(CheckVal) ->
        #state{nsearchers=NSearchers} = p2phun_swarm:my_state(Id0),
        ?assertEqual(NSearchers, CheckVal)
    end,
    CheckNSearchers(3),
    p2phun_swarm:nsearchers(Id0, 1),
    CheckNSearchers(1),
    p2phun_swarm:nsearchers(Id0, 5),
    CheckNSearchers(5),
    p2phun_swarm:nsearchers(Id0, 5),
    CheckNSearchers(5),
    shutdown_nodes(NodePids).
