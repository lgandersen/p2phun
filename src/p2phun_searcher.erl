-module(p2phun_searcher).
-include("peer.hrl").

-behaviour(gen_server).

-import(p2phun_utils, [floor/1]).
%% API functions
-export([start_link/2, find/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {my_id, cache, id2find, caller_pid, peer_pid}).
-record(lookup, {type, key2find, caller_pid}).

%%%===================================================================
%%% API functions
%%%===================================================================

-spec start_link(MyId :: id(), Cache :: table()) -> {ok, pid()} | ignore | {error, Error :: term()}.
start_link(MyId, Cache) ->
    gen_server:start_link(?MODULE, [MyId, Cache], []).

-spec find(pid(), {find_node, id()}) -> ok.
find(SearcherPid, {find_node, NodeId2Find}) ->
    gen_server:cast(SearcherPid, #lookup{type=node, key2find=NodeId2Find, caller_pid=self()}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([MyId, Cache]) -> {ok, #state{my_id=MyId, cache=Cache}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(#lookup{type=node, key2find=NodeId2Find, caller_pid=CallerPid}, State) ->
    NewState = prepare_next_peer(State#state{caller_pid=CallerPid, id2find=NodeId2Find}),
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({got_hello, NodeId2Find}, #state{peer_pid=PeerPid, id2find=NodeId2Find, caller_pid=CallerPid} = State) ->
    CallerPid ! #search_findings{searcher=self(), type=node_found, data=PeerPid},
    {noreply, State#state{id2find=undefined, caller_pid=undefined, peer_pid=undefined}};
handle_info({got_hello, PeerId}, #state{my_id=MyId, peer_pid=PeerPid, id2find=NodeId, caller_pid=CallerPid} = State) ->
    NewState = case p2phun_peer:find_peer(PeerPid, NodeId) of
        {peers_closest, Peers} ->
            CallerPid ! #search_findings{searcher=self(), type=nodes_closer, data=Peers},
            prepare_next_peer(State);
        {found_node, #peer{address=Address, server_port=Port}} when Port =:= none ->
            prepare_next_peer(State);
        {found_node, #peer{address=Address, server_port=Port}} ->
            {ok, NewPeerPid} = p2phun_peer_pool:connect_and_notify_when_connected(MyId, Address, Port),
            State#state{peer_pid=NewPeerPid};
        Msg ->
            lager:info("Repsonse not understood: ~p", [Msg]),
            State
    end,
    p2phun_peer:close_connection(PeerPid), % Should we close the connection here?
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
prepare_next_peer(#state{my_id=MyId, caller_pid=CallerPid} = State) ->
    NewState = case p2phun_swarm:next_peer(MyId) of
        no_peer_found ->
            CallerPid ! #search_findings{searcher=self(), type=no_more_peers_in_cache},
            State#state{peer_pid=undefined, id2find=undefined, caller_pid=undefined};
        #peer{address=Address, server_port=Port, pid=none} ->
            {ok, PeerPid} = p2phun_peer_pool:connect_and_notify_when_connected(MyId, Address, Port),
            State#state{peer_pid=PeerPid};
        #peer{pid=PeerPid} ->
            #peer_state{peer_id=PeerId} = p2phun_peer:my_state(PeerPid),
            self() ! {got_hello, PeerId},
            State#state{peer_pid=PeerPid}
    end,
    NewState.
