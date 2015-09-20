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
        #node_config{id=3, ip="127.0.0.1", port=5003, initial_peers=[{"127.0.0.1", 5002}]} % {"127.0.0.1", 5001},
        ],
    {ok, SupPid} = p2phun_sup:start_link(Nodes),
    lists:foreach(fun bootstrap_list/1, Nodes),
    {ok, SupPid}.

bootstrap_list(#node_config{id=Id, initial_peers=Peers} = _Node) ->
    Connect = fun ({Address, Port} = _Peer) -> p2phun_peer_pool:connect(Id, Address, Port) end,
    lists:foreach(Connect, Peers).

stop(_State) ->
    ok.
