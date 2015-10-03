-module(p2phun_peer_connection).
-behaviour(gen_server).
-behaviour(ranch_protocol).
-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").


%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
%% Startup

-export([start_link/4, start_link/3, close_connection/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, init/4, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {my_id, peer_id, peer_pid, transport, address, port, sup_pid}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [Ref, Socket, Transport, Opts]).

start_link(Address, Port, Opts) ->
    gen_server:start_link(?MODULE, [Address, Port, Opts], []).

close_connection(Pid) ->
    gen_server:cast(Pid, close_connection).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
%% They connect
init(Ref, Sock, Transport, [MyId] = _Opts) ->
    ok = proc_lib:init_ack({ok, self()}),
    %% Perform any required state initialization here.
    {ok, [{Address, Port}]} = inet:peernames(Sock),
    State = initialize(MyId, Sock, Transport, false, undefined),
    ok = Transport:setopts(Sock, [binary, {packet, 4}, {active, once}]),
    ok = ranch:accept_ack(Ref),
    gen_server:enter_loop(?MODULE, [], State).


%% We connect
init([Address, Port, #{my_id := MyId, sup_pid := SupPid} = _Opts]) ->
    case gen_tcp:connect(Address, Port, [binary, {packet, 4}, {active, once}], 10000) of
        {ok, Sock} -> 
            State = initialize(MyId, Sock, gen_tcp, true, SupPid),
            {ok, State};
        {error, Reason} ->
            {stop, {connection_error, Reason}}
    end.

initialize(MyId, Sock, Transport, WeConnected, SupPid) ->
    {ok, [{Address, Port}]} = inet:peernames(Sock),
    PeerState= #peerstate{
        my_id=MyId,
        we_connected=WeConnected,
        send=fun(Msg) -> Transport:send(Sock, Msg) end,
        address=Address,
        port=Port,
        connection_pid=self()},
    {ok, PeerPid} = p2phun_peer:start_link(PeerState),
    #state{
        transport=Transport,
        my_id=MyId,
        address=Address,
        port=Port,
        peer_pid=PeerPid,
        sup_pid=SupPid}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.
handle_cast(close_connection,#state{my_id=MyId, peer_id=PeerId} = State) ->
    close_connection_(MyId, PeerId),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({tcp, Sock, RawData}, #state{my_id=MyId, peer_pid=PeerPid, sup_pid=SupPid} = State) ->
    NewState = case binary_to_term(RawData) of
        {hello, #hello{id=PeerId} = HelloMsg} ->
            p2phun_peer:got_hello(PeerPid, {HelloMsg, SupPid}),
            spawn_link(p2phun_peer_manager, init, [0, MyId, PeerPid]),
            State#state{peer_id=PeerId};
        ping ->
            p2phun_peer:send_pong(PeerPid), State;
        pong ->
            p2phun_peer:got_pong(PeerPid), State;
       request_peerlist ->
            p2phun_peer:send_peerlist(PeerPid), State;
       {peer_list, Peers} ->
            p2phun_peer:got_peerlist(PeerPid, Peers), State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]), State
    end,
    inet:setopts(Sock, [{active, once}]),
    {noreply, NewState};
handle_info({tcp_closed, _Socket}, #state{my_id=MyId, peer_id=PeerId} = State) ->
    close_connection_(MyId, PeerId),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
close_connection_(MyId, PeerId) ->
    case PeerId of
        undefined -> ok;
        _ -> p2phun_peertable:delete_peers(MyId, [PeerId])
    end,
    supervisor:terminate_child(p2phun_utils:id2proc_name(p2phun_peer_pool, MyId), self()).
