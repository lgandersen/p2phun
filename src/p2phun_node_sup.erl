-module(p2phun_node_sup).

-behaviour(supervisor).

-include("peer.hrl").

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor

%% ===================================================================
%% API functions
%% ===================================================================

start_link(#node_config{id=Id} = Node, RoutingTableSpec) ->
    supervisor:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Node, RoutingTableSpec]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([#node_config{id=Id, address={_Ip, Port}} = _Node, RoutingTableSpec]) ->
    NodeProcesses = [
        #{% peertable
            id => {peertable, Id},
            start => {p2phun_peertable, start_link, [Id, RoutingTableSpec]},
            restart => permanent,
            shutdown => 2000,
            type => worker
        },
        #{% port listener
            id => {ranch_listener, Id},
            start => {ranch, start_listener, [{p2phun_peer_pool, Id}, 2, ranch_tcp, [{port, Port}], p2phun_peer_pool, [Id]]},
            restart => permanent,
            shutdown => 2000,
            type => supervisor
        },
        #{% peer pool
            id => {peer_pool, Id},
            start => {p2phun_peer_pool, start_link, [Id]},
            restart => permanent,
            shutdown => 2000,
            type => supervisor
        },
        #{% peer connections manager
            id => {p2phun_connections_manager, Id},
            start => {p2phun_connections_manager, start_link, [Id, Port]},
            restart => permanent,
            shutdown => 2000,
            type => worker
        }
        ],
    {ok, {{rest_for_one, 5, 10}, NodeProcesses}}.
