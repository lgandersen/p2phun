-module(p2phun_peer_pool).

-behaviour(ranch_protocol).
-behaviour(supervisor).

-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").

%% API
-export([start_link/1, connect/4]).

% Ranch callback
-export([start_link/4]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, temporary, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

-type connect_opts() :: sync | async_silent | async_notify.

%% @doc Start Pool supervisor.
start_link(MyId) ->
    lager_info(MyId, "Starting up!"),
    supervisor:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, []).

%% Connect to a new peer
-spec connect(MyId::id(), Address::nonempty_string(), Port::inet:port_number(), Opts::connect_opts()) -> {ok, pid()} | {error, term()}.
connect(MyId, Address, Port, async_silent) ->
    connect_(MyId, Address, Port, []);
connect(MyId, Address, Port, async_notify) ->
    connect_(MyId, Address, Port, [?NOTIFY_WHEN(got_hello)]);
connect(MyId, Address, Port, sync) ->
    {ok, _ConnectionPid} = connect(MyId, Address, Port, async_notify),
    receive
        ?NOTIFICATION(got_hello, Msg) -> Msg
    after 2000 -> {error, timeout}
    end.

connect_(MyId, Address, Port, Callers) ->
    lager_info(MyId, "Connecting to peer on ~p:~p.", [Address, Port]),
    supervisor:start_child(?MODULE_ID(MyId), [Address, Port, #{my_id=>MyId, callers=>Callers}]).

%% @private
%% Ranch callback
-spec start_link(ListenerPid :: pid(), Socket :: inet:socket(), Transport :: term(), Opts :: [id()]) -> {ok, pid()}.
start_link(ListenerId, Socket, Transport, [MyId] = Opts) ->
    {ok, [{Address, Port}]} = inet:peernames(Socket),
    lager_info(MyId, "Incoming peer on ~p:~p.", [Address, Port]),
    supervisor:start_child(?MODULE_ID(MyId), [ListenerId, Socket, Transport, Opts]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init(_Id) ->
    {ok, {{simple_one_for_one, 5, 10}, [?CHILD(p2phun_peer, worker)]}}.
