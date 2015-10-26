-module(p2phun_peer).
-behaviour(gen_fsm).

%% Api function exports
-export([start_link/4, start_link/3, send_peerlist/1, request_peerlist/1, ping/1, pong/1]).

%% gen_fsm exports
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3, code_change/4]).

%% State function exports
-export([awaiting_hello/2, connected/2, connected/3]).

-import(p2phun_utils, [lager_info/3, lager_info/2]).
-include("peer.hrl").

-record(state, {my_id, peer_id, we_connected, send, address, port, transport, sock, last_timestamp=-1, callers=[]}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [{we_received_connection, Ref, Socket, Transport, Opts}]).

start_link(Address, Port, Opts) ->
    gen_fsm:start_link(p2phun_peer, {we_connect, Address, Port, Opts}, []).

request_peerlist(PeerPid) ->
    gen_fsm:send_event(PeerPid, {request_peerlist, self()}),
    receive {got_peerlist, Peers} -> ok end,
    Peers.

ping(PeerPid) ->
    gen_fsm:send_event(PeerPid, {request_pong, self()}),
    receive got_pong -> ok
    after 5000 -> ping_timeout end.

%% ------------------------------------------------------------------
%% Troll API Function Definitions
%% (sending them out of context should produce errors)
%% ------------------------------------------------------------------
pong(PeerPid) ->
    gen_fsm:send_all_state_event(PeerPid, pong).

send_peerlist(PeerPid) ->
    gen_fsm:send_all_state_event(PeerPid, send_peerlist).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------
init({we_received_connection, Ref, Socket, Transport, [MyId] = _Opts}) ->
    ok = proc_lib:init_ack({ok, self()}),
    ok = Transport:setopts(Socket, [binary, {packet, 4}, {active, once}]),
    State = initialize(MyId, Socket, Transport, false, []),
    ok = ranch:accept_ack(Ref),
    gen_fsm:enter_loop(?MODULE, [], awaiting_hello, State);
init({we_connect, Address, Port, #{my_id := MyId, callers := Callers} = _Opts}) ->
    case gen_tcp:connect(Address, Port, [binary, {packet, 4}, {active, once}], 10000) of
        {ok, Sock} ->
            State = initialize(MyId, Sock, gen_tcp, true, Callers),
            send_hello(State),
            {ok, awaiting_hello, State};
        {error, Reason} ->
            {stop, {connection_error, Reason}}
    end;
init(State) ->
    lager:error("State '~p' unparseable", [State]),
    {stop, state_unparseable}.

initialize(MyId, Sock, Transport, WeConnected, Callers) ->
    {ok, [{Address, Port}]} = inet:peernames(Sock),
    #state{
        my_id=MyId,
        we_connected=WeConnected,
        address=Address,
        port=Port,
        transport=Transport,
        sock=Sock,
        callers=Callers}.

handle_event(pong, StateName, State) ->
    send(pong, State),
    {next_state, StateName, State};
handle_event(send_peerlist, StateName, State) ->
    send_peerlist_(State, -1),
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, _StName, StData) ->
    {stop, unimplemented, StData}.

handle_info({tcp, Sock, RawData}, StateName, #state{my_id=MyId} = State) ->
    NewState = case binary_to_term(RawData) of
        {hello, #hello{id=PeerId} = HelloMsg} ->
            gen_fsm:send_event(self(), {got_hello, HelloMsg}),
            spawn_link(p2phun_peer_manager, init, [0, MyId, self()]),
            State#state{peer_id=PeerId};
        ping ->
            send(pong, State), State;
        pong ->
            gen_fsm:send_event(self(), got_pong), State;
       {request_peerlist, {peer_age_above, TimeStamp}} ->
            send_peerlist_(State, TimeStamp), State;
       {peer_list, Peers} ->
            gen_fsm:send_event(self(), {got_peerlist, Peers}), State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]), State
    end,
    inet:setopts(Sock, [{active, once}]),
    {next_state, StateName, NewState};
handle_info({tcp_closed, _Socket}, _StateName, State) ->
    {stop, connection_closed, State};
handle_info(_Info, _StName, StData) ->
    {stop, unrecognized_message_received, StData}.

terminate(_Reason, _StName, _StData) -> ok.

code_change(_OldVsn, StName, StData, _Extra) -> {ok, StName, StData}.

%% ------------------------------------------------------------------
%% gen_fsm State Function Definitions
%% ------------------------------------------------------------------
awaiting_hello(
    {got_hello, #hello{id=PeerId, server_port=ListeningPort}},
    #state{my_id=MyId, address=Address, port=Port, callers=Callers} = State) ->
    Peer = #peer{id=PeerId, address=Address, connection_port=Port, server_port=ListeningPort, peer_pid=self(), time_added=erlang:system_time()},
    case p2phun_peertable:add_peer_if_possible(MyId, Peer) of
        peer_added ->
            NewCallers = notify_and_remove_callers(request_hello, {ok, got_hello}, Callers);
        FailureReason ->
            NewCallers = notify_and_remove_callers(request_hello, {error, FailureReason}, Callers),
            close_connection_(MyId, PeerId)
    end,
    case State#state.we_connected of
      false -> send_hello(State);
      true -> ok
    end,
    lager_info(MyId, "Got hello from node ~p", [p2phun_utils:b64(PeerId)]),
    {next_state, connected, State#state{peer_id=PeerId, callers=NewCallers}};
awaiting_hello(SomeEvent, #state{my_id=MyId} = State) ->
    lager_info(MyId, "Awaited hello, got '~p'.", [SomeEvent]),
    {stop, unexpected_event, State}.

connected({request_pong, CallersPid}, #state{callers=Callers} = State) ->
    send(ping, State),
    {next_state, connected, State#state{callers=add_caller({request_pong, CallersPid}, Callers)}};
connected({request_peerlist, CallersPid}, #state{callers=Callers, last_timestamp=TimeStamp} = State) ->
    send({request_peerlist, {peer_age_above, TimeStamp}}, State),
    {next_state, connected, State#state{callers=add_caller({request_peerlist, CallersPid}, Callers)}};
connected(got_pong, #state{callers=Callers} = State) ->
    NewCallers = notify_and_remove_callers(request_pong, got_pong, Callers),
    {next_state, connected, State#state{callers=NewCallers}};
connected({got_peerlist, Peers}, #state{callers=Callers} = State) ->
    NewCallers = notify_and_remove_callers(request_peerlist, {got_peerlist, Peers}, Callers),
    NewTimeStamp = update_timestamp(Peers, State),
    {next_state, connected, State#state{callers=NewCallers, last_timestamp=NewTimeStamp}};
connected(SomeEvent, #state{my_id=MyId} = State) ->
    lager_info(MyId, "Unexpected event '~p'.", [SomeEvent]),
    {stop, unexpected_event, State}.

connected(_SomeEvent, _From, State) ->
    {next_state, connected, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
send_hello(#state{my_id=MyId} = State) ->
    ListeningPort = p2phun_node_configuration:listening_port(MyId),
    HelloMsg = #hello{id=MyId, server_port=ListeningPort},
    send({hello, HelloMsg}, State).

send_peerlist_(State, TimeStamp) ->
    Peers = [Peer#peer{connection_port=none, peer_pid=none} || Peer <- p2phun_peertable:fetch_all_servers(State#state.my_id, TimeStamp)],
    send({peer_list, Peers}, State).


send(Msg, #state{transport=Transport, sock=Sock} = _S) ->
    Transport:send(Sock, term_to_binary(Msg)).

add_caller(Call, Callers) ->
    [Call|Callers].

update_timestamp(Peers, State) ->
    TimeStamps = [Peer#peer.time_added || Peer <- Peers],
    case erlang:length(TimeStamps) of
        0 -> State#state.last_timestamp;
        _ -> lists:max(TimeStamps)
    end.

notify_and_remove_callers(RequestType, Event, Callers) ->
    lists:filter(
        fun({Request, CallerPid}) ->
            case RequestType =:= Request of
                true -> CallerPid ! Event, false;
                false -> true
            end
        end, Callers).

close_connection_(MyId, PeerId) ->
    case PeerId of
        undefined -> ok;
        _ -> p2phun_peertable:delete_peers(MyId, [PeerId])
    end,
    lager_info(MyId, "Shutting me down!"),
    supervisor:terminate_child(p2phun_utils:id2proc_name(p2phun_peer_pool, MyId), self()).
