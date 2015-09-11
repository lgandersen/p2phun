-module(p2phun_node_sup).

-behaviour(supervisor).

-include("peer.hrl").

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(#node_config{id=Id} = Node) ->
    supervisor:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Node]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([#node_config{id=Id, port=Port} = _Node]) ->
    NodeProcesses = [
        {% peertable
            {peertable, Id},
            {p2phun_peertable, start_link, [Id]},
            permanent, 2000, worker, []
        },
        {% port listener
            {ranch_listener, Id},
            {ranch, start_listener, [{p2phun_peer_pool, Id}, 2, ranch_tcp, [{port, Port}], p2phun_peer_pool, [Id]]},
            permanent, 2000, supervisor, []
        },
        {% peer pool
            {peer_pool, Id},
            {p2phun_peer_pool, start_link, [Id]},
            permanent, 2000, supervisor, []
        },
        {% peer configuration
            {peer_configuration, Id},
            {p2phun_node_configuration, start_link, [Id, Port]},
            permanent, 2000, supervisor, []
        }
        ],
    {ok, {{rest_for_one, 5, 10}, NodeProcesses}}.
