-module(p2phun_peer).
-behaviour(gen_fsm).
-include("peer.hrl").

%% Api function exports
-export([
    start_link/4, % ranch callback from listening socket
    start_link/3, % we initiate connection
    close_connection/1,
    find_peer/2,
    request_peerlist/1,
    ping/1,
    my_state/1
    ]).

%% gen_fsm exports
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3, code_change/4]).

%% State function exports
-export([awaiting_hello/2, connected/2, connected/3]).

-import(p2phun_peertable_operations, [
    fetch_last_fetched_peer_/2,
    fetch_all_servers_/2,
    fetch_peers_closest_to_id_/4
    ]).

-import(p2phun_utils, [
    lager_info/3,
    lager_info/2
    ]).

-type search_result() :: {peers_closest, [peer()]} | {found_node, peer()}.
-type send_result() :: ok | {error, closed | inet:posix()}.

-define(STATE, #peer_state).


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-spec start_link(Ref :: pid(), Socket :: inet:socket(), Transport :: term(), Opts :: [id()]) -> pid().
start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [{we_received_connection, Ref, Socket, Transport, Opts}]).

-spec start_link(Address :: nonempty_string(), Port :: inet:port_number(), Opts :: [id()]) ->
    {ok, pid()} | ignore | {error, error()}.
start_link(Address, Port, Opts) ->
    gen_fsm:start_link(p2phun_peer, {we_connect, Address, Port, Opts}, []).

-spec ping(pid()) -> ok | ping_timeout.
ping(PeerPid) ->
    gen_fsm:send_event(PeerPid, {from_pid, self(), #msg{kind=request, type=ping}}),
    receive {ping, none} -> ok
    after 5000 -> ping_timeout end.

-spec request_peerlist(pid()) -> [peer()] | error.
request_peerlist(PeerPid) ->
    gen_fsm:send_event(PeerPid, {from_pid, self(), #msg{kind=request, type=peer_list}}),
    receive
      {peer_list, Peers} ->
        lager:info("Received peerlist of peers: ~p", [Peers]), Peers
    end.

-spec find_peer(PeerPid::pid(), Id2Find::id()) -> search_result().
find_peer(PeerPid, Id2Find) ->
    gen_fsm:send_event(PeerPid, {from_pid, self(), #msg{kind=request, type=find_node, data=Id2Find}}),
    receive {find_node, Result} -> Result end.

-spec close_connection(pid()) -> ok.
close_connection(PeerPid) ->
    gen_fsm:stop(PeerPid).

-spec my_state(pid()) -> ?STATE{}.
my_state(PeerPid) ->
    gen_fsm:sync_send_all_state_event(PeerPid, get_state).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------
init({we_received_connection, Ref, Socket, Transport, [MyId]}) ->
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
    ?STATE{
        my_id=MyId,
        we_connected=WeConnected,
        address=Address,
        port=Port,
        transport=Transport,
        sock=Sock,
        callers=Callers}.

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(get_state, _From, StateName, State) ->
    {reply, State, StateName, State};
handle_sync_event(Msg, _From, StateName, State) ->
    lager:info("Msg not understood: ~p", [Msg]),
    {reply, ok, StateName, State}.

handle_info({tcp, Sock, RawData}, StateName, State) ->
    NewState = case binary_to_term(RawData) of
        {hello, #hello{id=PeerId} = HelloMsg} ->
            gen_fsm:send_event(self(), {got_hello, HelloMsg}),
            State?STATE{peer_id=PeerId};
        #msg{kind=request} = Msg ->
            gen_fsm:send_event(self(), {from_peer, Msg}), State;
        #msg{} = Msg ->
            gen_fsm:send_event(self(), Msg), State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]), State
    end,
    inet:setopts(Sock, [{active, once}]),
    {next_state, StateName, NewState};
handle_info({tcp_closed, _Socket}, _StateName, State) ->
    {stop, {shutdown, connection_closed}, State};
handle_info(_Info, _StName, StData) ->
    {stop, unrecognized_message_received, StData}.

terminate(normal, _StateName, ?STATE{my_id=MyId, peer_id=PeerId, transport=Transport, sock=Sock}) ->
    Transport:close(Sock),
    p2phun_routingtable:delete_peers(MyId, [PeerId]), % FIXME should it delete or just update it as not-connected.
    lager:info("~p-->~p: Shutting me down!", [MyId, PeerId]);
terminate({shutdown, already_in_table}, awaiting_hello, ?STATE{my_id=MyId, transport=Transport, sock=Sock}) ->
    Transport:close(Sock),
    lager_info(MyId, "This peer is already in our routing table.");
terminate({shutdown, slots_full}, awaiting_hello, ?STATE{my_id=MyId, transport=Transport, sock=Sock}) ->
    Transport:close(Sock),
    lager_info(MyId, "There wasn't room for us in the peers routing table.");
terminate({shutdown, connection_closed}, _StateName, ?STATE{my_id=MyId, peer_id=PeerId, transport=Transport, sock=Sock}) ->
    Transport:close(Sock),
    lager_info(MyId, "MYID ~p table.", [MyId]),
    p2phun_routingtable:delete_peers(MyId, [PeerId]);
terminate(Error, _StateName, ?STATE{my_id=MyId, peer_id=PeerId}) ->
    lager_info(MyId, "-> ~p And unexpexted error occured: ~p", [PeerId, Error]),
    ok.

code_change(_OldVsn, StName, StData, _Extra) -> {ok, StName, StData}.

%% ------------------------------------------------------------------
%% gen_fsm State Function Definitions
%% ------------------------------------------------------------------
awaiting_hello(
    {got_hello, #hello{id=PeerId, server_port=ListeningPort}},
    ?STATE{my_id=MyId, address=Address, port=Port} = State) ->
    lager_info(MyId, "Got hello from node ~p", [PeerId]),
    Peer = #peer{id=PeerId, address=Address, connection_port=Port, server_port=ListeningPort, pid=self(), time_added=erlang:system_time()},
    case p2phun_routingtable:add_peer_if_possible(MyId, Peer) of
        peer_added ->
            NewCallers = notify_and_remove_callers(got_hello, {ok, {PeerId, self()}}, State),
            case State?STATE.we_connected of
              false -> send_hello(State);
              true -> ok
            end,
            {next_state, connected, State?STATE{peer_id=PeerId, callers=NewCallers}};
        FailureReason ->
            notify_and_remove_callers(got_hello, {error, FailureReason}, State),
            send(#msg{kind=connection_control, type=closing_connection, data=FailureReason}, State),
            {stop, {shutdown, FailureReason}, State}
    end;
awaiting_hello(#msg{type=closing_connection, data=Reason}, ?STATE{my_id=MyId} = State) ->
    lager_info(MyId, "Closing while awaiting hello. Reason from peer: ~p", [Reason]),
    notify_and_remove_callers(got_hello, {error, Reason}, State),
    {stop, {shutdown, Reason}, State};
awaiting_hello(SomeEvent, ?STATE{my_id=MyId} = State) ->
    lager_info(MyId, "Awaited hello, got '~p'.", [SomeEvent]),
    {stop, unexpected_event, State}.

connected({from_peer, Msg}, State) ->
    respond_to_peer_request(Msg, State),
    {next_state, connected, State};
connected({from_pid, RequestersPid, Msg}, State) ->
    NewState = forward_request_to_peer(Msg, RequestersPid, State),
    {next_state, connected, NewState};
connected(#msg{kind=response} = Msg, State) ->
    NewCallers = forward_response_to_pid(Msg, State),
    {next_state, connected, State?STATE{callers=NewCallers}};
connected(#msg{type=closing_connection, data=Reason}, ?STATE{my_id=MyId} = State) ->
    lager_info(MyId, "Closing connection '~p'.", [Reason]),
    {stop, closing_connection, State};
connected(SomeEvent, ?STATE{my_id=MyId} = State) ->
    lager_info(MyId, "Unexpected event '~p'.", [SomeEvent]),
    {stop, unexpected_event, State}.

connected(_SomeEvent, _From, State) ->
    {next_state, connected, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec send_hello(?STATE{}) -> ok | send_result().
send_hello(?STATE{my_id=MyId} = State) ->
    ListeningPort = p2phun_routingtable:server_port(MyId),
    HelloMsg = #hello{id=MyId, server_port=ListeningPort},
    send({hello, HelloMsg}, State).

-spec respond_to_peer_request(Request :: #msg{}, ?STATE{}) -> ok | {error, closed | inet:posix()}.
respond_to_peer_request(#msg{type=ping}, State) ->
    send(#msg{kind=response, type=ping}, State);
respond_to_peer_request(#msg{type=peer_list, data={peer_age_above, TimeStamp}}, State) ->
    send_peerlist_(TimeStamp, State);
respond_to_peer_request(#msg{type=find_node, data=Id2Find}, State) ->
    search_node_and_send_result(Id2Find, State).

-spec send_peerlist_(TimeStamp :: integer(), State :: ?STATE{}) -> send_result().
send_peerlist_(TimeStamp, ?STATE{my_id=MyId} = State) ->
    Peers = [Peer#peer{connection_port=none, pid=none} || Peer <- fetch_all_servers_(TimeStamp, ?ROUTINGTABLE(MyId))],
    send(#msg{kind=response, type=peer_list, data=Peers}, State).

-spec search_node_and_send_result(NodeId2Find :: id(), ?STATE{}) -> send_result().
search_node_and_send_result(NodeId2Find, ?STATE{my_id=MyId} = State) ->
    % Worst distance that should be acceptable (Should be dynamically defined at some point)
    MaxDistance = p2phun_utils:floor(?KEYSPACE_SIZE / 2),
    Peers = fetch_peers_closest_to_id_(?ROUTINGTABLE(MyId), NodeId2Find, MaxDistance, 10),
    SearchResult = case lists:keyfind(NodeId2Find, 2, Peers) of
        false -> {peers_closest, [P#peer{connection_port=none, pid=none} || P <- Peers]};
        Node -> {found_node, Node}
    end,
    send(#msg{kind=response, type=find_node, data=SearchResult}, State).

-spec forward_request_to_peer(Msg :: #msg{}, RequestersPid :: pid(), ?STATE{}) -> ?STATE{}.
forward_request_to_peer(#msg{type=peer_list, data=none} = Msg, RequestersPid,
                        ?STATE{my_id=MyId, peer_id=PeerId} = State) ->
    Msg1 = Msg#msg{data={peer_age_above, fetch_last_fetched_peer_(?ROUTINGTABLE(MyId), PeerId)}},
    forward_request_to_peer(Msg1, RequestersPid, State);
forward_request_to_peer(#msg{type=Type} = Msg, RequestersPid,
                        ?STATE{callers=PendingRequests, my_id=MyId, peer_id=PeerId} = State) ->
    lager_info(MyId, "Forwarding req. to peer ~p: ~p", [PeerId, Msg]),
    send(Msg, State),
    State?STATE{callers=[{Type, RequestersPid} | PendingRequests]}.

-spec forward_response_to_pid(Msg :: #msg{}, ?STATE{}) -> [{msg_type(), pid()}].
forward_response_to_pid(#msg{type=peer_list, data=Peers}, ?STATE{my_id=MyId, peer_id=PeerId} = State) ->
    p2phun_routingtable:update_timestamps(MyId, PeerId, Peers), %FIXME no need to send Peers, just find the proper timestamp
    notify_and_remove_callers(peer_list, Peers, State);
forward_response_to_pid(#msg{type=Type, data=Data}, State) ->
    notify_and_remove_callers(Type, Data, State).

-spec send(Msg:: term(), State :: ?STATE{}) -> send_result().
send(Msg, ?STATE{transport=Transport, sock=Sock}) ->
    Transport:send(Sock, term_to_binary(Msg)).

-spec notify_and_remove_callers(ResponseType :: msg_type(), Result :: term(), ?STATE{}) -> [{msg_type(), pid()}].
notify_and_remove_callers(ResponseType, Result, ?STATE{callers=Callers}) ->
    lists:filter(
        fun({RequestType, CallerPid}) ->
            case ResponseType =:= RequestType of
                true ->
                    CallerPid ! {ResponseType, Result}, false;
                false ->
                    true
            end
        end, Callers).
