-module(p2phun_connections_manager).
-behaviour(gen_server).
-include("peer.hrl").

-import(p2phun_utils, [lager_info/3, lager_info/2]).
-import(p2phun_peertable_operations, [
    fetch_all_peers_to_ping_/2,
    fetch_all_peers_to_ask_for_peers_/2,
    peers_not_in_table_/2
    ]).


%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([reminder/1]).

-record(state, {my_id, reminder_pid}).

%%%===================================================================
%%% API
%%%===================================================================

-spec start_link(id()) -> {ok, pid()} | ignore | {error, error()}.
start_link(Id) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id]) ->
    ReminderPid = spawn_link(?MODULE, reminder, [self()]),
    {ok, #state{my_id=Id, reminder_pid=ReminderPid}}.

handle_call(_Request, _From, State) ->
    {reply, error, State}.

handle_cast(plz_tend_peers, #state{my_id=MyId} = State) ->
    manage_peerlist_requests(MyId),
    manage_peer_pinging(MyId),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(Info, #state{my_id=MyId} = State) ->
    lager_info(MyId, "Message '~p' not understod.", [Info]),
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec reminder(pid()) -> no_return().
reminder(Pid) ->
    timer:sleep(2000),
    gen_server:cast(Pid, plz_tend_peers),
    reminder(Pid).

-spec manage_peer_pinging(MyId::id()) -> ok.
manage_peer_pinging(MyId) ->
    PeerPids = fetch_all_peers_to_ping_(?ROUTINGTABLE(MyId), 2000),
    lists:foreach(fun(PeerPid) ->
        case p2phun_peer:ping(PeerPid) of
            ping_timeout ->
                lager:info("Peer not responding to pong. I should deal with this.");
            ok -> ok
        end
    end, PeerPids).

-spec manage_peerlist_requests(MyId::id()) -> ok.
manage_peerlist_requests(MyId) ->
    PeerPids = fetch_all_peers_to_ask_for_peers_(?ROUTINGTABLE(MyId), 2000),
    lists:foreach(fun(PeerPid) -> request_peers_and_connect(MyId, PeerPid) end, PeerPids).

-spec request_peers_and_connect(MyId::id(), PeerPid::pid()) -> ok.
request_peers_and_connect(MyId, PeerPid) ->
    case p2phun_peer:request_peerlist(PeerPid) of
        error -> lager:info("An error occured during peerlist request");
        Peers ->
            Peers2Add = lists:filter(
                fun(#peer{id=Id} = _P) -> Id =/= MyId end,
                peers_not_in_table_(?ROUTINGTABLE(MyId), Peers)), %<-- this should probably be checke JUST before attempting to connect
            lists:foreach(
                fun(#peer{address=Address, server_port=Port}=_Peer) -> p2phun_peer_pool:connect(MyId, Address, Port) end,
                Peers2Add)
    end.
