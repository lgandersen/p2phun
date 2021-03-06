-module(p2phun_node_sup).

-behaviour(supervisor).

-include("peer.hrl").

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

-spec start_link(node_config()) -> {ok, pid()}.
start_link(#{id:=Id} = NodeCfg) ->
    supervisor:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [NodeCfg]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([#{opts:=[no_manager]} = NodeCfg]) ->
    {ok, {{rest_for_one, 5, 10}, mandatory_child_specs(NodeCfg)}};
init([#{opts:=[]} = NodeCfg]) ->
    {ok, {{rest_for_one, 5, 10}, mandatory_child_specs(NodeCfg) ++ manager_child_spec(NodeCfg)}}.

mandatory_child_specs(#{id:=Id, port:=Port, routingtable_cfg:=RoutingTableCfg}) ->
        [#{% peertable
            id => {peertable, Id},
            start => {p2phun_routingtable, start_link, [Id, RoutingTableCfg, Port]},
            restart => permanent,
            shutdown => 2000,
            type => worker
        },
        % port listener
        ranch:child_spec(?PEERPOOL(Id), 2, ranch_tcp, [{port, Port}], p2phun_peer_pool, [Id]),
        #{% peer pool
            id => ?PEERPOOL(Id),
            start => {p2phun_peer_pool, start_link, [Id]},
            restart => permanent,
            shutdown => 2000,
            type => supervisor
        },
        #{% Swarm query-layer
            id => ?SWARM(Id),
            start => {p2phun_swarm, start_link, [Id, 3]}, % integer is number of searcher-processes.
            restart => permanent,
            shutdown => 2000,
            type => worker
        }
        ].

manager_child_spec(#{id:=Id} = _NodeCfg) ->
    [#{ % peer connections manager
        id => {p2phun_connections_manager, Id},
        start => {p2phun_connections_manager, start_link, [Id]},
        restart => permanent,
        shutdown => 2000,
        type => worker
    }].
