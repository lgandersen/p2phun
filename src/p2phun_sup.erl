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
    NodeSupervisors = lists:map(
        fun(#node_config{id=Id} = Node) ->
            {{peertable, Id}, {p2phun_node_sup, start_link, [Node]}, permanent, 2000, supervisor, []}
        end,
        Nodes
        ),
    {ok, {{one_for_one, 5, 10}, NodeSupervisors}}.
