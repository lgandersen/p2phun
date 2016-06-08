-module(p2phun_testtools).

-include("peer.hrl").

-export([
     spawn_node/2,
     shutdown_nodes/1,
     shutdown_node/1,
     create_nodes/2,
     connection/2,
     connect/2
    ]).

spawn_node(Id, RoutingTableUpdates) ->
    RoutingTableSpec = [{space_size, 64}, {number_of_smallbins, 2}, {bigbin_nodesize, 2}, {smallbin_nodesize, 3}, {bigbin_spacesize, 32}],
    ReplaceOption = fun ({Name, _} = Opt, RTSpec) -> lists:keyreplace(Name, 1, RTSpec, Opt) end,
    RoutingTableSpec1 = lists:foldl(ReplaceOption, RoutingTableSpec, RoutingTableUpdates),
    {ok, Pid} = p2phun_node_sup:create_node(#{id=>Id, port=>5000 + Id, opts=>[no_manager], routingtable_cfg=>maps:from_list(RoutingTableSpec1)}),
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
    {ok, {IdServer, ConnectionPid}} = p2phun_peer_pool:connect(IdClient, ?LOCALHOST, 5000 + IdServer, sync),
    ConnectionPid.

connect(IdClient, IdServer) ->
    p2phun_peer_pool:connect(IdClient, ?LOCALHOST, 5000 + IdServer, sync).
