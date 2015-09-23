-module(p2phun_peertable).
-behaviour(gen_server).

-import(p2phun_utils, [lager_info/3]).
-include("peer.hrl").

-include_lib("stdlib/include/ms_transform.hrl").

-record(state, {tablename, id}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1, add_peers/2, delete_peers/2, fetch_peer/2, fetch_all/1, fetch_all_servers/1, peers_not_in_table/2, insert_if_not_exists/2]).

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

insert_if_not_exists(MyId, PeerId) ->
    gen_server:call(?MODULE_ID(MyId), {insert_if_not_exists, PeerId}).

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
    Tablename = p2phun_utils:id2proc_name(peers, Id),
    ets:new(Tablename, [ordered_set, named_table, {keypos, 2}]),
    {ok, #state{id=Id, tablename=Tablename}}.

handle_call({fetch_peer, PeerId}, _From, State) ->
    {reply, fetch_peer_(PeerId, State), State};
handle_call({insert_if_not_exists, PeerId}, _From, State) ->
    {reply, insert_if_not_exists_(PeerId, State), State};
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
    add_peers_(Peers, State),
    {noreply, State};
handle_cast({delete_peers, Peers}, State) ->
    delete_peers_(Peers, State),
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

add_peers_(Peers, S) ->
    ets:insert(S#state.tablename, Peers).

delete_peers_(Peers, S) ->
    lists:foreach(fun(Peer) -> ets:delete(S#state.tablename, Peer) end, Peers).

fetch_peer_(PeerId, S) ->
    ets:lookup(S#state.tablename, PeerId).

insert_if_not_exists_(PeerId, S) ->
    case fetch_peer_(PeerId, S) of
        [] -> 
            add_peers_(#peer{id=PeerId}, S),
            peer_inserted;
        _ ->
            peer_exists
    end.

peers_not_in_table_(Tablename, Peers) ->
    NotInTable =
        fun(#peer{id=Id} = _Peer) ->
            case ets:lookup(Tablename, Id) of
                [] -> true;
                _ -> false
            end
        end,
    lists:filter(NotInTable, Peers).

%peer2record(Peer) when is_record(Peer, peer) -> Peer;
%peer2record({Id, Address, Port} = _Peer) ->
%    #peer{id=Id, address=Address, server_port=Port}.
