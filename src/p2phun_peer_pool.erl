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

%% ===================================================================
%% API functions
%% ===================================================================

%% @doc Start Pool supervisor.
start_link(Id) ->
    lager:info("Starting peer no. ~p\n", [Id]),
    supervisor:start_link({local, p2phun_utils:id2proc_name(?MODULE, Id)}, ?MODULE, []).

%% @private 
%% Ranch callback
start_link(ListenerId, Socket, Transport, [Id] = Opts) ->
    lager:info("Incoming peer for id ~p!\n", [Id]),
    supervisor:start_child(p2phun_utils:id2proc_name(?MODULE, Id), [ListenerId, Socket, Transport, Opts]).

%% Connect to a new peer
connect(Address, Port, [Id] = _Opts) ->
    supervisor:start_child(p2phun_utils:id2proc_name(?MODULE, Id), [Address, Port, Id]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init(_Id) ->
    {ok, {{simple_one_for_one, 5, 10}, [?CHILD(p2phun_peer_connection, worker)]}}.
