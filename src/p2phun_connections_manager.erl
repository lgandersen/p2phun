-module(p2phun_connections_manager).
-behaviour(gen_server).
-include("peer.hrl").

-import(p2phun_utils, [lager_info/3, lager_info/2]).
%% API
-export([start_link/2, listening_port/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([reminder/1]).

-record(state, {my_id, listening_port, reminder_pid}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Id, ListeningPort) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, ListeningPort], []).

listening_port(Id) ->
    gen_server:call(?MODULE_ID(Id), listening_port).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id, ListeningPort]) ->
    ReminderPid = spawn_link(?MODULE, reminder, [self()]),
    {ok, #state{my_id=Id, listening_port=ListeningPort, reminder_pid=ReminderPid}}.

handle_call(listening_port, _From, State) ->
    {reply, State#state.listening_port, State};
handle_call(_Request, _From, State) ->
    {reply, error, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(plz_tend_peers, #state{my_id=MyId} = State) ->
    handle_peer_requests(MyId),
    handle_peer_pinging(MyId),
    {noreply, State};
handle_info(Info, #state{my_id=MyId} = State) ->
    lager_info(MyId, "Message '~p' not understod.", [Info]),
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
reminder(Pid) ->
    timer:sleep(1000),
    Pid ! plz_tend_peers,
    reminder(Pid).

handle_peer_pinging(MyId) ->
    PeerPids = p2phun_peertable:dirty_fetch_all_peers_to_ping(MyId, 2000),
    lists:foreach(ping_peer(PeerPid), PeerPids).

ping_peer(PeerPid) ->
    case p2phun_peer:ping(PeerPid) of
        ping_timeout ->
            lager:info("Peer not responding to pong. I should deal with this.");
        ok -> ok
    end.

handle_peer_requests(MyId) ->
    PeerPids = p2phun_peertable:dirty_fetch_all_peers_to_ask_for_peers(MyId, 2000),
    lists:foreach(fun(PeerPid) -> request_peers_and_connect(MyId, PeerPid) end, PeerPids).

request_peers_and_connect(MyId, PeerPid) ->
    Peers = p2phun_peer:request_peerlist(PeerPid),
    Peers2Add = lists:filter(
        fun(#peer{id=Id} = _P) -> Id =/= MyId end,
        p2phun_peertable:peers_not_in_table(MyId, Peers)),
    lists:foreach(
        fun(#peer{address=Address, server_port=Port}=_Peer) -> p2phun_peer_pool:connect(MyId, Address, Port) end,
        Peers2Add).
