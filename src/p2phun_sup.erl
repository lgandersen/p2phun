-module(p2phun_sup).

-behaviour(supervisor).

-include("peer.hrl").

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(Nodes) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Nodes]).


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([Nodes]) ->
    PeerTable = fun(#node_config{id=Id} = _Node) ->
        {
         {peertable, Id},
         {p2phun_peertable, start_link, [Id]},
         permanent, 2000, worker, [routingtable]
        }
        end,
    PeerTables = [PeerTable(Node) || Node <- Nodes],
    Listener = fun(#node_config{id=Id, port=Port} = _Node) ->
        {
         {ranch_listener, Id},
         {ranch, start_listener, [{p2phun_peer_pool, Id}, 2, ranch_tcp, [{port, Port}], p2phun_peer_pool, [Id]]},
         permanent, 2000, supervisor, [ranch]
        }
        end,
    Listeners = [Listener(Node) || Node <- Nodes],
    Pool = fun(#node_config{id=Id} = _Node) ->
        {
         {peer_pool, Id},
         {p2phun_peer_pool, start_link, [Id]},
         permanent, 2000, supervisor, [p2phun_peer_pool]
        }
        end,
    Pools = [Pool(Node) || Node <- Nodes],
    {ok, {{one_for_one, 5, 10}, PeerTables ++ Listeners ++ Pools}}.
