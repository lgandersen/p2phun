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
    %[{smallbin_nodesize, 3}, {bigbin_nodesize, 10}, {bigbin_spacesize, 70368744177664}, {number_of_smallbins, 3}, {space_size, 281474976710656}]
init([#node_config{id=Id, address={_Ip, Port}} = _Node, RoutingTableSpec]) ->
   %#{smallbin_nodesize:=SmallBin_NodeSize, bigbin_nodesize:=BigBin_NodeSize, bigbin_spacesize:=BigBin_SpaceSize, number_of_smallbins:=NumberOfSmallBins, space_size:=SpaceSize} = _RTSpec]) ->
    NodeProcesses = [
        #{% peertable
            id => {peertable, Id},
            start => {p2phun_peertable, start_link, [Id, RoutingTableSpec]},%, SpaceSize, BigBin_SpaceSize, BigBin_NodeSize, NumberOfSmallBins, SmallBin_NodeSize]},
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
        #{% peer configuration
            id => {peer_configuration, Id},
            start => {p2phun_node_configuration, start_link, [Id, Port]},
            restart => permanent,
            shutdown => 2000,
            type => supervisor
        }
        ],
    {ok, {{rest_for_one, 5, 10}, NodeProcesses}}.
