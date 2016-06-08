-module(p2phun_sup).

-behaviour(supervisor).

-include("peer.hrl").

%% API
-export([create_node/1, start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================
start_link(JsonAPIPort) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [JsonAPIPort]).

-spec create_node(node_config()) -> {ok, pid()}.
create_node(NodeCfg) ->
    supervisor:start_child(?MODULE, node_child(NodeCfg)).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([JsonAPIPort]) ->
    JsonApi = ranch:child_spec(json_api_listener, 1, ranch_tcp, [{port, JsonAPIPort}], p2phun_json_api, []),
    {ok, {{one_for_one, 5, 10}, [JsonApi]}}.

node_child(#{id:=Id} = NodeCfg) ->
         #{% peertable
             id => {node, Id},
             start => {p2phun_node_sup, start_link, [NodeCfg]},
             restart => permanent,
             shutdown => 2000,
             type => supervisor
        }.
