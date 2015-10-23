-module(p2phun_peer_pool).

-behaviour(ranch_protocol).
-behaviour(supervisor).

-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").

%% API
-export([start_link/1, connect/3, connect_sync/3]).

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
start_link(MyId) ->
    lager_info(MyId, "Starting up!"),
    supervisor:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, []).

%% @private 
%% Ranch callback
start_link(ListenerId, Socket, Transport, [MyId] = Opts) ->
    lager_info(MyId, "Incoming peer."),
    supervisor:start_child(?MODULE_ID(MyId), [ListenerId, Socket, Transport, Opts]).

%% Connect to a new peer
connect(MyId, Address, Port) ->
    supervisor:start_child(?MODULE_ID(MyId), [Address, Port, #{my_id => MyId, callers => []}]).

connect_sync(MyId, Address, Port) ->
    {ok, Child} = supervisor:start_child(?MODULE_ID(MyId), [Address, Port, #{my_id => MyId, callers => [{request_hello, self()}]}]),
    receive
        {ok, got_hello} -> {connected, Child};
        {error, Reason} -> {error, Reason}
    end.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init(_Id) ->
    {ok, {{simple_one_for_one, 5, 10}, [?CHILD(p2phun_peer, worker)]}}.
