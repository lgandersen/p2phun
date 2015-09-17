-module(p2phun_peer_pool).

-behaviour(ranch_protocol).
-behaviour(supervisor).

%% API
-export([start_link/1, connect/3]).

% Ranch callback
-export([start_link/4]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, temporary, 5000, Type, [I]}).
-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).

%% ===================================================================
%% API functions
%% ===================================================================

%% @doc Start Pool supervisor.
start_link(MyId) ->
    lager:info("Starting peer no. ~p\n", [MyId]),
    supervisor:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, []).

%% @private 
%% Ranch callback
start_link(ListenerId, Socket, Transport, [MyId] = Opts) ->
    lager:info("Incoming peer for id ~p!\n", [MyId]),
    supervisor:start_child(?MODULE_ID(MyId), [ListenerId, Socket, Transport, Opts]).

%% Connect to a new peer
connect(MyId, Address, Port) ->
    supervisor:start_child(?MODULE_ID(MyId), [Address, Port, MyId]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init(_Id) ->
    {ok, {{simple_one_for_one, 5, 10}, [?CHILD(p2phun_peer_connection, worker)]}}.
