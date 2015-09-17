-module(p2phun_peertable).
-behaviour(gen_server).

-import(p2phun_utils, [id2proc_name/2]).

-include_lib("stdlib/include/ms_transform.hrl").

-define(MODULE_ID(Id), id2proc_name(?MODULE, Id)).

-include("peer.hrl").

-record(state, {tablename, id}).
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1, add_peers/2, delete_peers/2, fetch_peer/2, fetch_all/1, fetch_all_servers/1, distance/2, peers_not_in_table/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Id) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id], []).

add_peers(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {add_peers, Peers}).

delete_peers(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {delete_peers, Peers}).

fetch_peer(MyId, PeerId) ->
    gen_server:call(?MODULE_ID(MyId), {fetch_peer, PeerId}).

fetch_all(MyId) ->
    gen_server:call(?MODULE_ID(MyId), fetch_all).

fetch_all_servers(MyId) ->
    gen_server:call(?MODULE_ID(MyId), fetch_all_servers).

peers_not_in_table(MyId, Peers) ->
    gen_server:call(?MODULE_ID(MyId), {peers_not_in_table, Peers}).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Id]) ->
    Tablename = id2proc_name(peers, Id),
    ets:new(Tablename, [ordered_set, named_table, {keypos, 2}]),
    {ok, #state{id=Id, tablename=Tablename}}.

handle_call({fetch_peer, PeerId}, _From, State) ->
    Peer = ets:lookup(State#state.tablename, PeerId),
    {reply, Peer, State};
handle_call(fetch_all, _From, State) ->
    Peers = [Peer || [Peer] <- ets:match(State#state.tablename, '$1')],
    {reply, Peers, State};
handle_call(fetch_all_servers, _From, State) ->
    MatchSpec = ets:fun2ms(fun(#peer{server_port=Port} = Peer) when (Port =/= none) -> Peer end),
    Peers = [Peer || Peer <- ets:select(State#state.tablename, MatchSpec)],
    {reply, Peers, State};
handle_call({peers_not_in_table, Peers}, _From, State) ->
    PeersNotInTable = peers_not_in_table_(State#state.tablename, Peers),
    {reply, PeersNotInTable, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({add_peers, Peers}, State) ->
    add_peers_(State#state.tablename, Peers),
    {noreply, State};
handle_cast({delete_peers, Peers}, State) ->
    delete_peers_(State#state.tablename, Peers),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

add_peers_(Tablename, Peers) ->
    PeersTmp = [peer2record(Peer) || Peer <- Peers],
    ets:insert(Tablename, PeersTmp).

delete_peers_(Tablename, Peers) ->
    DeletePeer = fun(Peer) -> ets:delete(Tablename, peer2record(Peer)) end,
    lists:foreach(DeletePeer, Peers).

peers_not_in_table_(Tablename, Peers) ->
    NotInTable =
        fun(#peer{id=Id} = _Peer) ->
            case ets:lookup(Tablename, Id) of
                [] -> true;
                _ -> false
            end
        end,
    lists:filter(NotInTable, Peers).

distance(BaseId, Id) ->
    case BaseId < Id of
        true -> Id - BaseId;
        false -> (?MAX_PEERID - BaseId) + Id
    end.

peer2record(#peer{id=_Id, server_port=_Port, address=_Address} = Peer) ->
    Peer;
peer2record({Id, Address, Port} = _Peer) ->
    #peer{id=Id, address=Address, server_port=Port}.
