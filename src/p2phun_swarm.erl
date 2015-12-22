-module(p2phun_swarm).
-include("peer.hrl").

% When this gets more complicated we should switch to poolboy!
-behaviour(gen_server).

%% API functions
-export([
    start_link/1,
    find_node/2,
    add_peers_not_in_table/2,
    next_peer/1]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).


%% Import general table functions
-import(p2phun_peertable_operations, [
    peers_not_in_table_/2, update_peer_/3, sudo_add_peers_/2,
    fetch_peers_closest_to_id_and_not_visited/3.
    ]).

-record(state, {my_id, cache, id2find, searchers, nsearchers, responses, caller_pid}).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(MyId) ->
    gen_server:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, [MyId], []).

find_node(MyId, Id2Find) ->
    gen_server:cast(?MODULE_ID(MyId), {find_node, Id2Find, self()}). 
    receive
        {find_node_responses, Responses} -> Responses
    end.

add_peers_not_in_table(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {add_peers, Peers}).

next_peer(MyId) ->
    gen_server:cast(?MODULE_ID(MyId), next_peer).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([MyId]) ->
    NSearchers = 3, % This should be supplied on startup (and changed at will)
    Cache = ets:new(result_cache, [set, {keypos, 2}]),
    Searchers = lists:map(
        fun(_N) -> spawn_link(searcher(#state{my_id=MyId, cache=Cache})) end,
        lists:seq(1, NSearchers)),
    {ok, #state{my_id=MyId, cache=Cache, searchers=Searchers, nsearchers=NSearchers, responses=[]}}.

handle_cast({find_node, Id2Find, CallerPid}, _From, #state{my_id=MyId, searchers=Searchers} = State) ->
    ClosestPeers = dirty_fetch_peers_closest_to_id(
        ?PEER_TABLE(MyId), PeerId, p2phun_utils:floor(?KEYSPACE_SIZE / 2)),
    case lists:keyfind(Id2Find, 2, ClosestPeers) of
        Peer -> Peer;
        false ->
            sudo_add_peers_(ClosestPeers, Cache),
            lists:foreach(
                fun(SearcherPid) -> p2phun_searcher:find({node, Id2Find, self()}, SearcherPid) end,
                Searchers),
            awaiting_result()
    end,
    {noreply, State#state{caller_pid=CallerPid}}.

handle_call(next_peer, _From, #state{id2find=Id2Find, cache=Cache} = State) ->
    case fetch_peers_closest_to_id_and_not_visited(
        Cache, Id2Find, floor(?KEYSPACE_SIZE / 2), 1) of
        [Peer] ->
            update_peer_(Peer#peer.id, [{process_status, done}], Cache),
            {reply, Peer, State};
        [] -> 
            {reply, no_peer_found, State}
    end;
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({add_peers, Peers}, #state{my_id=MyId, cache=Cache} = State) ->
    NewPeers = peers_not_in_table_(Peers, Cache),
    sudo_add_peers_(NewPeers, Cache),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({result, Response}, State) ->
    NewState = handle_responses(Response, State),
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_responses(NewResponse, #state{responses=Responses, nsearchers=NSearchers, caller_pid=CallerPid} = State) ->
    ResponsesNew = [NewResponse, Responses];
    case length(ResponsesNew) of
        NSearchers ->
            % WHAT TO DO WITH CACHE?
            CallerPid ! {find_node_responses, ResponsesNew},
            State#state{responses=[], caller_pid=undefined, id2find=undefined};
        _ ->
            State#state{responses=ResponsesNew}
    end.
