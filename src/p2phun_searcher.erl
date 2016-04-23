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

-type result() :: {find_node, Id2Find :: id(), CallerPid :: pid()}.

%%%===================================================================
%%% API functions
%%%===================================================================

-spec start_link(MyId :: id(), Cache :: table()) -> {ok, pid()} | ignore | {error, Error :: term()}.
start_link(MyId, Cache) ->
    gen_server:start_link(?MODULE, [MyId, Cache], []).

-spec find(pid(), {find_node, id()}) -> ok.
find(SearcherPid, {find_node, NodeId}) ->
    gen_server:cast(SearcherPid, #lookup{type=node, key2find=NodeId, caller_pid=self()}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([MyId, Cache]) -> {ok, #state{my_id=MyId, cache=Cache}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(#lookup{type=node, key2find=NodeId, caller_pid=CallerPid}, State) ->
    NewState = prepare_next_peer(State#state{caller_pid=CallerPid, id2find=NodeId}),
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({ok, got_hello}, #state{peer_pid=PeerPid, id2find=NodeId, caller_pid=CallerPid} = State) ->
    % TODO check if this peer have the right node id and return the result
    NewState = case p2phun_peer:find_peer(PeerPid, NodeId) of
        {peers_closer, Peers} ->
            CallerPid ! #search_findings{searcher=self(), type=nodes_closer, data=Peers},
            p2phun_peer:close_connection(PeerPid),
            prepare_next_peer(State);
        {found_node, Node} ->
            CallerPid ! #search_findings{searcher=self(), type=node_found, data={Node, PeerPid}},
            State
    end,
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
        Peer ->
            #peer{address=Address, server_port=Port} = Peer,
            PeerPid = p2phun_peer_pool:connect_and_notify_when_connected(MyId, Address, Port),
            State#state{peer_pid=PeerPid}
    end,
    NewState.
