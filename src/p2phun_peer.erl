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
    ping/1
    ]).

%% gen_fsm exports
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3, code_change/4]).

%% State function exports
-export([awaiting_hello/2, connected/2, connected/3]).

%% Import routing table specific functions
-import(p2phun_peertable_operations, [
    delete_peers_/2,
    fetch_last_fetched_peer_/2,
    fetch_all_servers_/2,
    fetch_peers_closest_to_id_/4
    ]).

%% Import utils
-import(p2phun_utils, [lager_info/3, lager_info/2]).

-type msg_type() :: hello | ping | peer_list | find_node.
-type search_result() :: {peers_closer, [peer()]} | {found_node, peer()}.
-type send_result() :: ok | {error, closed | inet:posix()}.

-record(state, {my_id, peer_id, we_connected, send, address, port, transport, sock, callers=[]}).


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
    gen_fsm:send_event(PeerPid, {request_from_pid, self(), {ping, none}}),
    receive {got_pong, none} -> ok
    after 5000 -> ping_timeout end.

-spec request_peerlist(pid()) -> [peer()].
request_peerlist(PeerPid) ->
    gen_fsm:send_event(PeerPid, {request_from_pid, self(), {peer_list, {peer_age_above, supply_value}}}),
    receive
      {peer_list, Peers} ->
        lager:info("Received peerlist of peers: ~p", [Peers]),
        Peers
    end.

-spec find_peer(PeerPid::pid(), Id2Find::id()) -> search_result().
find_peer(PeerPid, Id2Find) ->
    gen_fsm:send_event(PeerPid, {request_from_pid, self(), {find_node, Id2Find}}),
    receive {find_node, Result} -> Result end.

-spec close_connection(pid()) -> ok.
close_connection(PeerPid) ->
    gen_fsm:stop(PeerPid).

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
    #state{
        my_id=MyId,
        we_connected=WeConnected,
        address=Address,
        port=Port,
        transport=Transport,
        sock=Sock,
        callers=Callers}.

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, _StName, StData) ->
    {stop, unimplemented, StData}.

handle_info({tcp, Sock, RawData}, StateName, State) ->
    NewState = case binary_to_term(RawData) of
        {hello, #hello{id=PeerId} = HelloMsg} ->
            gen_fsm:send_event(self(), {got_hello, HelloMsg}),
            State#state{peer_id=PeerId};
        {response, Response} ->
            send_event({response, Response}), State;
        {request, Request} ->
            send_event({request, Request}), State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]), State
    end,
    inet:setopts(Sock, [{active, once}]),
    {next_state, StateName, NewState};
handle_info({tcp_closed, _Socket}, _StateName, State) ->
    {stop, connection_closed, State};
handle_info(_Info, _StName, StData) ->
    {stop, unrecognized_message_received, StData}.

terminate(normal, _StateName, #state{my_id=MyId, peer_id=PeerId, transport=Transport, sock=Sock}) ->
    Transport:close(Sock),
    delete_peers_([PeerId], ?ROUTINGTABLE(MyId)), %FIXME should it delete or just update it as not-connected.
    lager_info(MyId, "Shutting me down!");
terminate(Error, _StateName, #state{my_id=MyId, peer_id=PeerId}) -> %, transport=Transport, sock=Sock}) ->
    lager_info(MyId, "-> ~p And unexpexted error occured: ~p", [p2phun_utils:b64(PeerId), Error]),
    ok.

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
            NewCallers = notify_and_remove_callers(hello, {ok, got_hello}, State);
        FailureReason ->
            NewCallers = notify_and_remove_callers(hello, {error, FailureReason}, State),
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

connected({request_from_peer, Request}, State) ->
    create_response_and_send_to_peer(Request, State),
    {next_state, connected, State};
connected({request_from_pid, RequestersPid, Request}, State) ->
    NewState = forward_request_to_peer(Request, RequestersPid, State),
    {next_state, connected, NewState};
connected({response, {ResponseType, Result}}, State) ->
    NewCallers = forward_response_to_pid(ResponseType, Result, State),
    {next_state, connected, State#state{callers=NewCallers}};
connected(SomeEvent, #state{my_id=MyId} = State) ->
    lager_info(MyId, "Unexpected event '~p'.", [SomeEvent]),
    {stop, unexpected_event, State}.

connected(_SomeEvent, _From, State) ->
    {next_state, connected, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec send_hello(#state{}) -> ok | send_result().
send_hello(#state{my_id=MyId} = State) ->
    ListeningPort = p2phun_routingtable:server_port(MyId),
    HelloMsg = #hello{id=MyId, server_port=ListeningPort},
    send({hello, HelloMsg}, State).

-spec send_event(Response :: term()) -> ok.
send_event({response, Response}) ->
    gen_fsm:send_event(self(), {response, Response});
send_event({request, Request}) ->
    gen_fsm:send_event(self(), {request_from_peer, Request}).

-spec forward_request_to_peer(Request :: term(), Requester :: pid(), #state{}) -> #state{}.
forward_request_to_peer({peer_list, {peer_age_above, supply_value}}, Requester, #state{my_id=MyId, peer_id=PeerId} = State) ->
    Request = {peer_list, {peer_age_above, fetch_last_fetched_peer_(?ROUTINGTABLE(MyId), PeerId)}},
    forward_request_to_peer(Request, Requester, State);
forward_request_to_peer(Request, RequestersPid, #state{callers=PendingRequests} = State) ->
    {Type, _} = Request,
    send({request, Request}, State),
    State#state{callers=[{Type, RequestersPid}|PendingRequests]}.

-spec create_response_and_send_to_peer(Request :: term(), #state{}) -> ok | {error, closed | inet:posix()}.
create_response_and_send_to_peer({ping, none}, State) ->
    send({response, {ping, none}}, State);
create_response_and_send_to_peer({peer_list, {peer_age_above, TimeStamp}}, State) ->
    send_peerlist_(TimeStamp, State), State;
create_response_and_send_to_peer({find_node, Id2Find}, State) ->
    search_node_and_send_result(Id2Find, State).

-spec forward_response_to_pid(ResponseType :: msg_type(), Result :: term(), #state{}) -> [{msg_type(), pid()}].
forward_response_to_pid(peer_list, Peers, #state{my_id=MyId, peer_id=PeerId} = State) ->
    p2phun_routingtable:update_timestamps(MyId, PeerId, Peers), %FIXME no need to send Peers, just find the proper timestamp
    notify_and_remove_callers(peer_list, Peers, State);
forward_response_to_pid(ResponseType, Result, State) ->
    notify_and_remove_callers(ResponseType, Result, State).

-spec send_peerlist_(TimeStamp :: integer(), State :: #state{}) -> send_result().
send_peerlist_(TimeStamp, #state{my_id=MyId} = State) ->
    Peers = [Peer#peer{connection_port=none, pid=none} || Peer <- fetch_all_servers_(TimeStamp, ?ROUTINGTABLE(MyId))],
    send({response, {peer_list, Peers}}, State).

-spec search_node_and_send_result(NodeId2Find :: id(), #state{}) -> send_result().
search_node_and_send_result(NodeId2Find, #state{my_id=MyId} = State) ->
    % Worst distance that should be acceptable (Should be dynamically defined at some point)
    MaxDistance = p2phun_utils:floor(?KEYSPACE_SIZE / 2),
    Peers = fetch_peers_closest_to_id_(MyId, NodeId2Find, MaxDistance, 10),
    SearchResult = case lists:keyfind(NodeId2Find, 2, Peers) of
        false -> {peers_closer, Peers};
        Node -> {found_node, Node}
    end,
    send({repsonse, {find_node, SearchResult}}, State).

-spec send(Msg:: term(), State :: #state{}) -> send_result().
send(Msg, #state{transport=Transport, sock=Sock}) ->
    Transport:send(Sock, term_to_binary(Msg)).

-spec notify_and_remove_callers(ResponseType :: msg_type(), Result :: term(), #state{}) -> [{msg_type(), pid()}].
notify_and_remove_callers(ResponseType, Result, #state{callers=Callers}) ->
    lists:filter(
        fun({RequestType, CallerPid}) ->
            case ResponseType =:= RequestType of
                true -> CallerPid ! {ResponseType, Result}, false;
                false -> true
            end
        end, Callers).
