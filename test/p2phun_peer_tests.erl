-module(p2phun_peer_tests).

-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(NODE(Id), #node_config{id=Id, address={"127.0.0.1", 5000 + Id}}).

spawn_node(Node, RoutingTableUpdates) ->
    RoutingTableSpec = [{space_size, 64}, {number_of_smallbins, 3}, {bigbin_nodesize, 2}, {smallbin_nodesize, 3}, {bigbin_spacesize, 32}],
    ReplaceOption = fun ({Name, _} = Opt, RTSpec) -> lists:keyreplace(Name, 1, RTSpec, Opt) end,
    RoutingTableSpec1 = lists:foldl(ReplaceOption, RoutingTableSpec, RoutingTableUpdates),
    {ok, Pid} = p2phun_node_sup:start_link_no_manager(Node, maps:from_list(RoutingTableSpec1)),
    Pid.


shutdown_node(NodePid) ->
    Ref = monitor(process, NodePid),
    unlink(NodePid),
    exit(NodePid, shutdown),
    receive
        {'DOWN', Ref, process, NodePid, _Reason} -> ok
    after 5000 ->
        error(exit_timeout)
    end.

handshake_test() ->
    application:ensure_started(ranch),
    Ids = [Id0, _Id1] = [0, 1],
    RoutingTableUpdates = [],
    NodePids = lists:map(fun(Id) -> spawn_node(?NODE(Id), RoutingTableUpdates) end, Ids),
    {connected, _ChildPid} = p2phun_peer_pool:connect_sync(Id0, "127.0.0.1", 5001),
    lists:foreach(fun(Id) -> ranch:stop_listener({ranch_listener, Id}) end, Ids),
    lists:foreach(fun shutdown_node/1, NodePids).


already_in_table_test() ->
    Ids = [Id0, Id1] = [0, 1],
    RoutingTableUpdates = [],
    NodePids = lists:map(fun(Id) -> spawn_node(?NODE(Id), RoutingTableUpdates) end, Ids),
    {connected, ChildPid} = p2phun_peer_pool:connect_sync(Id0, "127.0.0.1", 5001),
    {error, already_in_table} = p2phun_peer_pool:connect_sync(Id1, "127.0.0.1", 5000),
    lists:foreach(fun shutdown_node/1, NodePids),
    lists:foreach(fun(Id) -> ranch:stop_listener({p2phun_peer_pool, Id}) end, Ids).


table_full_test() ->
    Ids = [Id0, Id1, Id2] = [0, 1, 2],
    RoutingTableUpdates = [{bigbin_nodesize, 1}],
    NodePids = lists:map(fun(Id) -> spawn_node(?NODE(Id), RoutingTableUpdates) end, Ids),
    {connected, ChildPid} = p2phun_peer_pool:connect_sync(Id0, "127.0.0.1", 5001),
    {error, table_full} = p2phun_peer_pool:connect_sync(Id0, "127.0.0.1", 5002).
