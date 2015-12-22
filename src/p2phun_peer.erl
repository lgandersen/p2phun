-module(p2phun_peer).
-behaviour(gen_fsm).
-include("peer.hrl").

%% Api function exports
-export([
    start_link/4, % ranch callback from listening socket
    start_link/3, % we initiate connection
    close_connection/1,
    find_peer/2,
    send_peerlist/1,
    request_peerlist/1,
    ping/1,
    pong/1]).

%% gen_fsm exports
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3, code_change/4]).

%% State function exports
-export([awaiting_hello/2, connected/2, connected/3]).

%% Import routing table specific functions
-import(p2phun_peertable_operations, [
    delete_peers_/2,
    fetch_last_fetched_peer_/2,
    fetch_all_servers_/2,
    fetch_peers_closest_to_id_/4,
    update_peer_/3
    ]).

%% Import utils
-import(p2phun_utils, [lager_info/3, lager_info/2]).

-record(state, {my_id, peer_id, we_connected, send, address, port, transport, sock, callers=[]}).


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-spec start_link(Ref :: pid(), Socket :: inet:socket(), Transport :: term(), Opts :: [p2phun_types:id()]) -> pid().
start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [{we_received_connection, Ref, Socket, Transport, Opts}]).

start_link(Address, Port, Opts) ->
    gen_fsm:start_link(p2phun_peer, {we_connect, Address, Port, Opts}, []).

close_connection(PeerPid) ->
    gen_fsm:stop(PeerPid).

request_peerlist(PeerPid) ->
    gen_fsm:send_event(PeerPid, {request_peerlist, self()}),
    receive {got_peerlist, Peers} -> Peers end.

find_peer(PeerPid, Id2Find) ->
    gen_fsm:send_event(PeerPid, {find_node, Id2Find, self()}),
    receive {find_node_result, SearchResult} -> SearchResult end.

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
    Transport = gen_tcp,
    case Transport:connect(Address, Port, [binary, {packet, 4}, {active, once}], 10000) of
        {ok, Sock} ->
            State = initialize(MyId, Sock, Transport, true, Callers),
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
    send_peerlist_(-1, State),
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, _StName, StData) ->
    {stop, unimplemented, StData}.

handle_info({tcp, Sock, RawData}, StateName, State) ->
    NewState = case binary_to_term(RawData) of
        {hello, #hello{id=PeerId} = HelloMsg} ->
            gen_fsm:send_event(self(), {got_hello, HelloMsg}),
            State#state{peer_id=PeerId};
        ping ->
            send(pong, State), State;
        pong ->
            gen_fsm:send_event(self(), got_pong), State;
       {request_peerlist, {peer_age_above, TimeStamp}} ->
            send_peerlist_(TimeStamp, State), State;
       {peer_list, Peers} ->
            gen_fsm:send_event(self(), {got_peerlist, Peers}), State;
       {find, {node, NodeId}} ->
            search_node_and_send_result(NodeId, State);
       {find_node_result, Result} ->
            gen_fsm:send_event(self(), {find_node_result, Result}), State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]), State
    end,
    inet:setopts(Sock, [{active, once}]),
    {next_state, StateName, NewState};
handle_info({tcp_closed, _Socket}, _StateName, State) ->
    {stop, connection_closed, State};
handle_info(_Info, _StName, StData) ->
    {stop, unrecognized_message_received, StData}.

terminate(normal, _StateName, #state{my_id=MyId, peer_id=PeerId, transport=Transport, sock=Sock} = _State) ->
    Transport:close(Sock),
    delete_peers_([PeerId], ?ROUTINGTABLE(MyId)),
    lager_info(MyId, "Shutting me down!").

code_change(_OldVsn, StName, StData, _Extra) -> {ok, StName, StData}.

%% ------------------------------------------------------------------
%% gen_fsm State Function Definitions
%% ------------------------------------------------------------------
awaiting_hello(
    {got_hello, #hello{id=PeerId, server_port=ListeningPort}},
    #state{my_id=MyId, address=Address, port=Port} = State) ->
    Peer = #peer{id=PeerId, address=Address, connection_port=Port, server_port=ListeningPort, pid=self(), time_added=erlang:system_time()},
    case p2phun_routingtable:add_peer_if_possible(MyId, Peer) of
        peer_added ->
            NewCallers = notify_and_remove_callers(request_hello, {ok, got_hello}, State);
        FailureReason ->
            NewCallers = notify_and_remove_callers(request_hello, {error, FailureReason}, State),
            gen_fsm:stop(self())
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

connected({request_pong, CallersPid}, State) ->
    send(ping, State),
    {next_state, connected, State#state{callers=add_caller({request_pong, CallersPid}, State)}};
connected(got_pong, State) ->
    NewCallers = notify_and_remove_callers(request_pong, got_pong, State),
    {next_state, connected, State#state{callers=NewCallers}};
connected({request_peerlist, Caller}, #state{my_id=MyId, peer_id=PeerId} = State) ->
    TimeStamp = fetch_last_fetched_peer_(MyId, PeerId),
    send({request_peerlist, {peer_age_above, TimeStamp}}, State),
    {next_state, connected, State#state{callers=add_caller({request_peerlist, Caller}, State)}};
connected({got_peerlist, Peers}, State) ->
    NewCallers = notify_and_remove_callers(request_peerlist, {got_peerlist, Peers}, State),
    update_timestamps(Peers, State),
    {next_state, connected, State#state{callers=NewCallers}};
connected({find_node, NodeId, Caller}, State) ->
    send({find_node, NodeId}, State),
    {next_state, connected, State#state{callers=add_caller({request_peerlist, Caller}, State)}};
connected({find_node_result, Result}, State) ->
    NewCallers = notify_and_remove_callers(find_node, {got_result, Result}, State),
    {next_state, connected, State#state{callers=NewCallers}};
connected(SomeEvent, #state{my_id=MyId} = State) ->
    lager_info(MyId, "Unexpected event '~p'.", [SomeEvent]),
    {stop, unexpected_event, State}.

connected(_SomeEvent, _From, State) ->
    {next_state, connected, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
send_hello(#state{my_id=MyId} = State) ->
    ListeningPort = p2phun_routingtable:server_port(MyId),
    HelloMsg = #hello{id=MyId, server_port=ListeningPort},
    send({hello, HelloMsg}, State).

send_peerlist_(TimeStamp, #state{my_id=MyId} = State) ->
    Peers = [Peer#peer{connection_port=none, pid=none} || Peer <- fetch_all_servers_(TimeStamp, ?ROUTINGTABLE(MyId))],
    send({peer_list, Peers}, State).

search_node_and_send_result(NodeId, #state{my_id=MyId} = State) ->
    % Worst distance that should be acceptable (Should be dynamically defined at some point)
    MaxDistance = p2phun_utils:floor(?KEYSPACE_SIZE / 2),
    Peers = fetch_peers_closest_to_id_(MyId, NodeId, MaxDistance, 10),
    SearchResult = case lists:keyfind(NodeId, 2, Peers) of
        false -> {peers_closer, Peers};
        Node -> {found_node, Node}
    end,
    send({find_node_result, SearchResult}, State).

send(Msg, #state{transport=Transport, sock=Sock} = _S) ->
    Transport:send(Sock, term_to_binary(Msg)).

add_caller(Call, #state{callers=Callers} = _S) ->
    [Call|Callers].

update_timestamps([], #state{my_id=MyId, peer_id=PeerId} = _S) ->
    update_peer_(PeerId, [
        {last_peerlist_request, erlang:system_time(milli_seconds)},
        {last_spoke, erlang:system_time(milli_seconds)}], ?ROUTINGTABLE(MyId));
update_timestamps(Peers, #state{my_id=MyId, peer_id=PeerId} = _S) ->
    update_peer_(PeerId, [
        {last_peerlist_request, erlang:system_time(milli_seconds)},
        {last_spoke, erlang:system_time(milli_seconds)},
        {last_fetched_peer, lists:max([Peer#peer.time_added || Peer <- Peers])}
        ], ?ROUTINGTABLE(MyId)).

notify_and_remove_callers(RequestType, Event, #state{callers=Callers} = _S) ->
    lists:filter(
        fun({Request, CallerPid}) ->
            case RequestType =:= Request of
                true -> CallerPid ! Event, false;
                false -> true
            end
        end, Callers).
