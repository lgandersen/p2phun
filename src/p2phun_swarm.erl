-module(p2phun_swarm).
-include("peer.hrl").

% When this gets more complicated we should switch to poolboy!
-behaviour(gen_server).

%% API functions
-export([
    start_link/2,
    find_node/2,
    add_peers_not_in_table/2,
    next_peer/1,
    nsearchers/2,
    my_state/1]).

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

-record(state, {my_id, cache, id2find, searchers, nsearchers, responses, caller_pid}).

%%%===================================================================
%%% API functions
%%%===================================================================
-type response() :: no_node_found | {node_found, {NodeId :: id(), PeerPid :: pid()}}.

-spec start_link(id(), pos_integer()) -> {ok, pid()} | ignore | {error, error()}.
start_link(MyId, NSearchers) ->
    gen_server:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, [MyId, NSearchers], []).

-spec find_node(MyId :: id(), Id2Find :: id()) -> response().
find_node(MyId, Id2Find) ->
    gen_server:cast(?MODULE_ID(MyId), {find_node, Id2Find, self()}),
    receive
        {find_node_responses, Responses} -> Responses
    end.

-spec add_peers_not_in_table(MyId :: id(), Peers :: [#peer{}]) -> ok.
add_peers_not_in_table(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {add_peers, Peers}).

-spec next_peer(id()) -> no_peer_found | #peer{}.
next_peer(MyId) ->
    gen_server:call(?MODULE_ID(MyId), next_peer).

-spec nsearchers(id(), pos_integer()) -> ok.
nsearchers(MyId, NSearchers) ->
    gen_server:call(?MODULE_ID(MyId), {nsearchers, NSearchers}).

-spec my_state(id()) -> #state{}.
my_state(MyId) ->
    gen_server:call(?MODULE_ID(MyId), get_state).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([MyId, NSearchers]) ->
    State = #state{my_id=MyId, cache=ets:new(result_cache, [set, {keypos, 2}])},
    Searchers = create_searchers(NSearchers, State),
    {ok, State#state{searchers=Searchers, nsearchers=NSearchers, responses=[]}}.

handle_call(next_peer, _From, #state{id2find=Id2Find, cache=Cache} = State) ->
    case fetch_peers_closest_to_id_and_not_processed(
        Cache, Id2Find, p2phun_utils:floor(?KEYSPACE_SIZE / 2), 1) of
        [Peer] ->
            update_peer_(Cache, Peer#peer.id, [{processed, true}]),
            {reply, Peer, State};
        [] ->
            {reply, no_peer_found, State}
    end;
handle_call({nsearchers, NSearchsNew}, _From, State) ->
    {reply, ok, adjust_nsearchers(NSearchsNew, State)};
handle_call(get_state, _From, State) ->
    {reply, State, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({add_peers, Peers}, #state{cache=Cache} = State) ->
    NewPeers = peers_not_in_table_(Cache, Peers),
    sudo_add_peers_(Cache, NewPeers),
    {noreply, State};
handle_cast({find_node, Id2Find, CallerPid}, #state{my_id=MyId, id2find=Id2Find, searchers=Searchers, cache=Cache} = State) ->
    ClosestPeers = fetch_peers_closest_to_id_(
        ?ROUTINGTABLE(MyId), Id2Find, p2phun_utils:floor(?KEYSPACE_SIZE / 2), 15),
    case lists:keyfind(Id2Find, 2, ClosestPeers) of
        false ->
            sudo_add_peers_(Cache, ClosestPeers),
            lists:foreach(
                fun(SearcherPid) -> p2phun_searcher:find({node, Id2Find, self()}, SearcherPid) end,
                Searchers);
        Peer -> Peer
    end,
    {noreply, State#state{caller_pid=CallerPid}};
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
-spec handle_responses(response(), #state{}) -> #state{}.
handle_responses(NewResponse, #state{responses=Responses, nsearchers=NSearchers, caller_pid=CallerPid} = State) ->
    ResponsesNew = [NewResponse, Responses],
    case length(ResponsesNew) of
        NSearchers ->
            % WHAT TO DO WITH CACHE?
            CallerPid ! {find_node_responses, ResponsesNew},
            State#state{responses=[], caller_pid=undefined, id2find=undefined};
        _ ->
            State#state{responses=ResponsesNew}
    end.

-spec adjust_nsearchers(pos_integer(), #state{}) -> #state{}.
adjust_nsearchers(NSearchsNew, #state{nsearchers=NSearchsOld, searchers=Searchers} = State) when NSearchsNew < NSearchsOld ->
    Searchers2Remove = lists:nthtail(NSearchsNew, Searchers),
    lists:foreach(fun(Pid) -> exit(Pid, shutdown) end, Searchers2Remove),
    State#state{nsearchers=NSearchsNew, searchers=lists:sublist(Searchers, NSearchsNew)};
adjust_nsearchers(NSearchsNew, #state{nsearchers=NSearchsOld, searchers=Searchers} = State) when NSearchsNew > NSearchsOld ->
    NewSearchers = create_searchers(NSearchsNew - NSearchsOld, State),
    State#state{nsearchers=NSearchsNew, searchers=lists:append(Searchers, NewSearchers)};
adjust_nsearchers(NSearchsNew, #state{nsearchers=NSearchsOld} = State) when NSearchsNew =:= NSearchsOld ->
    State.

-spec create_searchers(pos_integer(), #state{}) -> [pid()].
create_searchers(Searchers2Create, #state{cache=Cache, my_id=MyId}) ->
    lists:map(
        fun(_N) -> spawn_link(p2phun_searcher, start_link, [MyId, Cache]) end,
        lists:seq(1, Searchers2Create)
     ).
