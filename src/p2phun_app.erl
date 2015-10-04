-module(p2phun_app).

-behaviour(application).

-include("peer.hrl").

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================
start() -> application:ensure_all_started(p2phun).

start(_StartType, _StartArgs) ->
    {ok, RoutingTableSpec} = application:get_env(p2phun, routing_table_config),
    {ok, Nodes} = application:get_env(p2phun, nodes),
    {ok, JsonApiConf} = application:get_env(p2phun, json_api_config),
    lager:info("Initial conditions: ~p", [Nodes]),
    {ok, SupPid} = p2phun_sup:start_link({Nodes, JsonApiConf, maps:from_list(RoutingTableSpec)}),
    lists:foreach(fun bootstrap_list/1, Nodes),
    {ok, SupPid}.

bootstrap_list(#node_config{id=Id, bootstrap_peers=Peers} = _Node) ->
    Connect = fun ({Address, Port} = _Peer) -> p2phun_peer_pool:connect_sync(Id, Address, Port) end,
    lists:foreach(Connect, Peers).

stop(_State) -> ok.
