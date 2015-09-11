-module(p2phun_app).

-behaviour(application).

-include("peer.hrl").

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================
start() ->
    application:ensure_all_started(p2phun).

start(_StartType, _StartArgs) ->
    Nodes = [
        #node_config{id=1, ip="127.0.0.1", port=5001, initial_peers=[{"127.0.0.1", 5002}]},
        #node_config{id=2, ip="127.0.0.1", port=5002, initial_peers=[]},%{"127.0.0.1", 5001}]},
        #node_config{id=3, ip="127.0.0.1", port=5003, initial_peers=[{"127.0.0.1", 5001}, {"127.0.0.1", 5002}]}
        ],
    Status = p2phun_sup:start_link(Nodes),
    ConnectionsToMake = lists:flatten(lists:map(fun bootstrap_list/1, Nodes)),
    lager:info("Initial conditions: ~p\n", [ConnectionsToMake]),
    lists:map(fun connect_to/1, ConnectionsToMake),
    Status.

bootstrap_list(#node_config{id=Id, initial_peers=Peers} = _Node) ->
    [{Id, Address, Port} || {Address, Port} <- Peers].

connect_to({ConnectersId, Address, Port} = _ConnectInfo) ->
    p2phun_peer_pool:connect(Address, Port, [ConnectersId]).

stop(_State) ->
    ok.
