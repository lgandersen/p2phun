-module(p2phun_peer_pool).

-behaviour(ranch_protocol).
-behaviour(supervisor).

-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").

%% API
-export([start_link/1, connect/3, connect_sync/3, connect_and_notify_when_connected/3]).

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
-spec start_link(ListenerPid :: pid(), Socket :: inet:socket(), Transport :: term(), Opts :: [id()]) -> {ok, pid()}.
start_link(ListenerId, Socket, Transport, [MyId] = Opts) ->
    {ok, [{Address, Port}]} = inet:peernames(Socket),
    lager_info(MyId, "Incoming peer on ~p:~p.", [Address, Port]),
    supervisor:start_child(?MODULE_ID(MyId), [ListenerId, Socket, Transport, Opts]).

%% Connect to a new peer
-spec connect(MyId :: id(), Address :: nonempty_string(), Port :: inet:port_number()) -> {ok, pid()} | {error, term()}.
connect(MyId, Address, Port) ->
    lager_info(MyId, "Connecting to peer on ~p:~p.", [Address, Port]),
    supervisor:start_child(?MODULE_ID(MyId), [Address, Port, #{my_id => MyId, callers => []}]).

-spec connect_and_notify_when_connected(MyId :: id(), Address :: nonempty_string(), Port :: inet:port_number()) -> {ok, pid()} | {error, term()}.
connect_and_notify_when_connected(MyId, Address, Port) ->
    supervisor:start_child(?MODULE_ID(MyId), [Address, Port, #{my_id => MyId, callers => [{hello, self()}]}]).

-spec connect_sync(MyId :: id(), Address :: nonempty_string(), Port :: inet:port_number()) -> {connected, pid()} | {error, term()}.
connect_sync(MyId, Address, Port) ->
    {ok, ChildPid} = connect_and_notify_when_connected(MyId, Address, Port),
    receive
        {ok, got_hello} -> {connected, ChildPid};
        {error, Reason} -> {error, Reason}
    end.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init(_Id) ->
    {ok, {{simple_one_for_one, 5, 10}, [?CHILD(p2phun_peer, worker)]}}.
