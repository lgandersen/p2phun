-module(p2phun_swarm).
-include("peer.hrl").

% When this gets more complicated we should switch to poolboy!
-behaviour(gen_server).

%% API functions
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).


%% Import general table functions
-import(p2phun_peertable_operations, [
    peers_not_in_table_/2, insert_if_not_exists_/2,
    fetch_all_servers_/2, update_peer_/3,
    peer_already_in_table_/2, fetch_peers_closest_to_id_/3,
    fetch_last_fetched_peer_/2, fetch_all_peers_to_ping_/2,
    fetch_all_peers_to_ask_for_peers_/2, fetch_peer_/2,
    fetch_all_/1, sudo_add_peers_/2, delete_peers_/2]).


-record(state, {my_id, cache, searchers, nsearchers, responses}).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(MyId) ->
    gen_server:start_link({local, ?MODULE_ID(MyId)}, ?MODULE, [MyId], []).

find_node(MyId, NodeId) ->
    gen_server:call(?MODULE_ID(MyId), {find_node, NodeId}) 

add_peers(ParentPid, Peers) ->

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

handle_call({find_node, NodeId}, _From, #state{my_id=MyId, searchers=Searchers} = State) ->
    ClosestTo = dirty_fetch_peers_closest_to_id(
        ?PEER_TABLE(MyId), PeerId, p2phun_utils:floor(?KEYSPACE_SIZE / 2)),
    case lists:keyfind(NodeId, 2, ClosestTo) of
        Peer -> Peer;
        false -> find_node(NodeId, ClosestTo, Searchers, State)
    end.
            
    %check if the Node is in our own list above, otherwise ask our neighbours, check if the node is there and if not, parse those down the searchers
    % NB! Should we try and connect to verify the validity of the node-information we find? IF it is possible.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
find_node(NodeId, [Peer|RestPeers], [Searcher|RestSearchers], State) ->
    Searcher ! {find_node, Peer, NodeId, self()},
    find_node(NodeId, RestPeers, RestSearchers, State);
find_node(NodeId, [], Searchers, State) -> find_node(NodeId, [], [], State);
find_node(NodeId, Peers, [], State) -> find_node(NodeId, [], [], State);
find_node(NodeId, [], [], State) ->
    receive 
        % here we should have several types of responses
        %{node_found, Peer} -> Peer; % Perhaps we should try an connect to it?
    end.

%% ALL THIS SHOULD BE WRAPPED IN GEN_SERVER
searcher(State) ->
    receive {find_node, Peer2Ask, NodeId, ParentPid} -> 
        runner_find_node(Peer2Ask, NodeId, ParentPid, State)  
    end.

runner_find_node(Peer2Ask, NodeId, ParentPid, #state{my_id=MyId, cache=Cache} = State) ->
    case p2phun_peer:find_peer(Peer2Ask#peer.pid, NodeId, self()) of
        {peers_closer, Peers} ->
            sudo_add_peers_(Peers, Cache),
            % It should be closer to what we've got already
            PeerPid = connect_next(fetch_peers_closest_to_id_(Cache, NodeId, Peer2Ask#peer.id));
        {found_node, NodeId} ->
            % check if 1) if it is a server and if so try to connect to its port, if it fails report that back
            %          2) otherwise report that it is not a server and return the node we are connected to atm which gave us the info
            ParentPid ! {node_found, NodeId} % this should be changed, see above
    end,

connect_next([Peer|RestOfPeers], #state{my_id=MyId} = State) ->
    #peer{address=Address, server_port=Port} = Peer,                
    case connect_sync(MyId, Address, Port) of
        {connected, PeerPid} -> PeerPid;
        {error, Reason} ->
            connect_next(RestOfPeers, State)
    end.
connect_next([], State) -> no_more_peers_lef_what_to_do. % Perhaps send a 'i'm done and found nothing'

% Content of SearchResult:
%        false -> {peers_closer, Peers};
%        Node -> {found_node, Node}

