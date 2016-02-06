-module(p2phun_node_sup).

-behaviour(supervisor).

-include("peer.hrl").

%% API
-export([start_link/2, start_link_no_manager/2]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor

%% ===================================================================
%% API functions
%% ===================================================================

start_link(#node_config{id=Id} = Node, RoutingTableSpec) ->
    supervisor:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Node, RoutingTableSpec]).

start_link_no_manager(#node_config{id=Id} = Node, RoutingTableSpec) ->
    supervisor:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Node, RoutingTableSpec, no_manager]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([Node, RoutingTableSpec, no_manager]) ->
    {ok, {{rest_for_one, 5, 10}, mandatory_child_specs(Node, RoutingTableSpec)}};
init([Node, RoutingTableSpec]) ->
    {ok, {{rest_for_one, 5, 10}, mandatory_child_specs(Node, RoutingTableSpec) ++ manager_child_spec(Node)}}.

mandatory_child_specs(#node_config{id=Id, address={_Ip, Port}} = _Node, RoutingTableSpec) ->
        [#{% peertable
            id => {peertable, Id},
            start => {p2phun_routingtable, start_link, [Id, RoutingTableSpec, Port]},
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
        }
        ].

manager_child_spec(#node_config{id=Id} = _Node) ->
    [#{ % peer connections manager
        id => {p2phun_connections_manager, Id},
        start => {p2phun_connections_manager, start_link, [Id]},
        restart => permanent,
        shutdown => 2000,
        type => worker
    }].
