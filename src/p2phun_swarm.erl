-module(p2phun_swarm).
-include("peer.hrl").

% When this gets more complicated we should switch to poolboy!
-behaviour(gen_server).

%% API functions
-export([
    start_link/2,
    find_node/2,
    add_peers_not_in_cache/2,
    next_peer/1,
    nsearchers/2,
    my_state/1,
    cache/1]).

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
    peers_not_in_table_/2,
    update_peer_/3,
    sudo_add_peers_/2,
    fetch_peers_closest_to_id_and_not_processed/4,
    fetch_peers_closest_to_id_/4
    ]).

-record(state, {my_id, cache, id2find, searchers, nsearchers, idle_searchers, caller_pid}).

-type response() :: no_node_found | {node_found, {NodeId :: id(), PeerPid :: pid()}}.

%%%===================================================================
%%% API functions
%%%===================================================================
-spec start_link(id(), pos_integer()) -> {ok, pid()} | ignore | {error, error()}.
start_link(MyId, NSearchers) ->
    gen_server:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, [MyId, NSearchers], []).

-spec find_node(MyId :: id(), Id2Find :: id()) -> response().
find_node(MyId, Id2Find) ->
    gen_server:cast(?MODULE_ID(MyId), {find_node, Id2Find, self()}),
    receive
        {find_node_responses, Responses} -> Responses
    end.

-spec add_peers_not_in_cache(MyId :: id(), Peers :: [#peer{}]) -> ok.
add_peers_not_in_cache(MyId, Peers) -> % Only used in testing atm.
    gen_server:cast(?MODULE_ID(MyId), {add_peers_not_in_cache, Peers}).

-spec next_peer(id()) -> no_peer_found | #peer{}.
next_peer(MyId) ->
    gen_server:call(?MODULE_ID(MyId), next_peer).

-spec nsearchers(id(), pos_integer()) -> ok.
nsearchers(MyId, NSearchers) ->
    gen_server:call(?MODULE_ID(MyId), {nsearchers, NSearchers}).

-spec my_state(id()) -> #state{}.
my_state(MyId) ->
    gen_server:call(?MODULE_ID(MyId), get_state).

-spec cache(id()) -> table().
cache(MyId) ->
    gen_server:call(?MODULE_ID(MyId), get_cache).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([MyId, NSearchers]) ->
    State = #state{my_id=MyId, cache=ets:new(result_cache, [set, {keypos, 2}])},
    Searchers = create_searchers(NSearchers, State),
    {ok, State#state{
           searchers=Searchers,
           nsearchers=NSearchers,
           idle_searchers=[],
           id2find=MyId % Makes it easier to test, will be reset after first search.
          }}.

handle_call(next_peer, _From, #state{id2find=Id2Find, cache=Cache} = State) ->
    case fetch_peers_closest_to_id_and_not_processed(
        Cache, Id2Find, p2phun_utils:floor(?KEYSPACE_SIZE / 2), 1) of
        [Peer] ->
            % Because of this update we need to do this at swarm proc to avoid two searchers
            % picking the same peer
            update_peer_(Cache, Peer#peer.id, [{processed, true}]),
            {reply, Peer, State};
        [] ->
            {reply, no_peer_found, State}
    end;
handle_call({nsearchers, NSearchsNew}, _From, State) ->
    {reply, ok, adjust_nsearchers(NSearchsNew, State)};
handle_call(get_cache, _From, #state{cache=Cache} = State) ->
    {reply, Cache, State};
handle_call(get_state, _From, State) ->
    {reply, State, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({add_peers_not_in_cache, Peers}, State) ->
    {noreply, add_peers_not_in_cache_(Peers, State)};
handle_cast({find_node, Id2Find, CallersPid}, #state{my_id=MyId, searchers=Searchers, cache=Cache} = State) ->
% TODO just send the result in case we already have it in our routingtable
    ClosestPeers = fetch_peers_closest_to_id_(
        ?ROUTINGTABLE(MyId), Id2Find, p2phun_utils:floor(?KEYSPACE_SIZE / 2), 15),
    case lists:keyfind(Id2Find, 2, ClosestPeers) of
        false ->
            sudo_add_peers_(Cache, ClosestPeers),
            lists:foreach(
                fun(SearcherPid) -> p2phun_searcher:find(SearcherPid, {find_node, Id2Find}) end,
                Searchers);
        Peer -> Peer
    end,
    {noreply, State#state{caller_pid=CallersPid}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(#search_findings{} = Findings, State) ->
    NewState = handle_findings(Findings, State),
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
-spec handle_findings(#search_findings{}, #state{}) -> #state{}.
handle_findings(_Findings, #state{caller_pid=undefined, id2find=undefined} = State) ->
% This should imply that a search is not undergoing. However, a searcher might have waited for a response before discovering that the cache is empty. 
% Thus, ignore its finding.
    State;
handle_findings(#search_findings{type=nodes_closer, data=Peers}, State) ->
    add_peers_not_in_cache_(Peers, State);
handle_findings(
  #search_findings{searcher=SearchersPid, type=node_found, data=NodeInfo},
  #state{cache=Cache, caller_pid=CallersPid, idle_searchers=IdleSearchers} = State) ->
    true = ets:delete_all_objects(Cache),
    CallersPid ! {result, {node_found, NodeInfo}},
    State#state{idle_searchers=[SearchersPid|IdleSearchers], caller_pid=undefined, id2find=undefined};
handle_findings(
  #search_findings{type=no_more_peers_in_cache, searcher=SearchersPid},
  #state{cache=Cache, nsearchers=NSearchers, caller_pid=CallersPid, idle_searchers=IdleSearchers} = State) when length(IdleSearchers) =:= NSearchers - 1 ->
    true = ets:delete_all_objects(Cache),
    CallersPid ! {result, no_node_found}, % we could also fetch the closest nodes before flushing cache and send it to the caller
    State#state{idle_searchers=[SearchersPid|IdleSearchers], caller_pid=undefined, id2find=undefined};
handle_findings(
  #search_findings{type=no_more_peers_in_cache, searcher=SearchersPid},
  #state{nsearchers=NSearchers, idle_searchers=IdleSearchers} = State) when length(IdleSearchers) < NSearchers - 1 ->
    State#state{idle_searchers=[SearchersPid|IdleSearchers]}.

-spec add_peers_not_in_cache_([#peer{}], #state{}) -> #state{}.
add_peers_not_in_cache_(Peers, #state{cache=Cache} = State) ->
    NewPeers = peers_not_in_table_(Cache, Peers),
    sudo_add_peers_(Cache, NewPeers),
    State.

-spec adjust_nsearchers(pos_integer(), #state{}) -> #state{}.
adjust_nsearchers(NSearchsNew, #state{nsearchers=NSearchsOld, searchers=Searchers} = State) when NSearchsNew < NSearchsOld ->
    Searchers2Remove = lists:nthtail(NSearchsNew, Searchers),
    lists:foreach(fun(Pid) -> unlink(Pid), exit(Pid, shutdown) end, Searchers2Remove),
    State#state{nsearchers=NSearchsNew, searchers=lists:sublist(Searchers, NSearchsNew)};
adjust_nsearchers(NSearchsNew, #state{nsearchers=NSearchsOld, searchers=Searchers} = State) when NSearchsNew > NSearchsOld ->
    NewSearchers = create_searchers(NSearchsNew - NSearchsOld, State),
    State#state{nsearchers=NSearchsNew, searchers=lists:append(Searchers, NewSearchers)};
adjust_nsearchers(NSearchsNew, #state{nsearchers=NSearchsOld} = State) when NSearchsNew =:= NSearchsOld ->
    State.

-spec create_searchers(pos_integer(), #state{}) -> [pid()].
create_searchers(Searchers2Create, #state{cache=Cache, my_id=MyId}) ->
    lists:map(
        fun(_N) -> {ok, Pid} = p2phun_searcher:start_link(MyId, Cache), Pid end,
        lists:seq(1, Searchers2Create)
     ).
