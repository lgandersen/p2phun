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

%%%===================================================================
%%% API functions
%%%===================================================================

%% -spec start_link() -> {ok, Pid} | ignore | {error, Error}
start_link(MyId, Cache) ->
    gen_server:start_link(?MODULE, [MyId, Cache], []).

find({node, Id2Find, CallerPid}, SearcherPid) ->
    gen_server:cast(SearcherPid, {find_node, Id2Find, CallerPid}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% -spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
init([MyId, Cache]) -> {ok, #state{my_id=MyId, cache=Cache}}.

%% -spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% -spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
handle_cast({find_node, NodeId, CallerPid}, State) ->
    NewState = State#state{caller_pid=CallerPid, id2find=NodeId},
    {ok, NewState} = prepare_next_peer(NewState),
    {noreply, NewState};
handle_cast(ask_next_node, State) ->
    {ok, NewState} = prepare_next_peer(State),
    {noreply, NewState}.

prepare_next_peer(#state{my_id=MyId, caller_pid=CallerPid} = State) ->
    case p2phun_swarm:next_peer(MyId) of
        no_peer_found ->
            NewState = State#state{peer_pid=undefined, id2find=undefined, caller_pid=undefined},
            CallerPid ! {result, no_node_found};
        Peer ->
            #peer{address=Address, server_port=Port} = Peer,
            PeerPid = p2phun_peer_pool:connect_and_notify_when_connected(MyId, Address, Port),
            NewState = State#state{peer_pid=PeerPid}
    end,
    {ok, NewState}.


%% -spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
handle_info({ok, got_hello}, #state{my_id=MyId, peer_pid=PeerPid, id2find=NodeId, caller_pid=CallerPid} = State) ->
    case p2phun_peer:find_peer(PeerPid, NodeId) of
        {peers_closer, Peers} ->
            p2phun_swarm:add_peers_not_in_table(MyId, Peers),
            p2phun_peer:close_connection(PeerPid),
            gen_server:cast(self(), ask_next_node);
        {found_node, NodeId} ->
            CallerPid ! {result, {node_found, {NodeId, PeerPid}}}
    end,
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%% -spec terminate(Reason, State) -> void()
terminate(_Reason, _State) ->
    ok.

%% -spec code_change(OldVsn, State, Extra) -> {ok, NewState}
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
