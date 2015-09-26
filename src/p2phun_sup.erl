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

start_link({Nodes, JsonApiConf}) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [{Nodes, JsonApiConf}]).


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([{Nodes, {_JsonAPIAddress, JsonAPIPort}}]) ->
     JsonApi =
        #{% port listener
            id => p2phun_json_api,
            start => {ranch, start_listener, [json_api_listener, 1, ranch_tcp, [{port, JsonAPIPort}], p2phun_json_api, []]}, %Evt. fix binary, {packet, 0}
            restart => permanent,
            shutdown => 2000,
            type => supervisor
        },
        %  id => ,
        %  start => {p2phun_json_api, start_link, [JsonAPIAddress, ]},
        %  restart => permanent,
        %  shutdown => 5000,
        %  type => worker
        %  },
    NodeSupervisors = lists:map(
        fun(#node_config{id=Id} = Node) ->
            #{id => {p2phun_node_supervisor, Id},
              start => {p2phun_node_sup, start_link, [Node]},
              restart => permanent,
              shutdown => 5000,
              type => supervisor}
        end,
        Nodes
        ),
    {ok, {{one_for_one, 5, 10}, [JsonApi | NodeSupervisors]}}.
