-module(p2phun_peer).
-behaviour(gen_fsm).

%% Api function exports
-export([start_link/1, got_hello/2, send_peerlist/1, request_peerlist/2, got_peerlist/2, got_pong/1, request_pong/2, send_pong/1]).

%% gen_fsm exports
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3, code_change/4]).

%% State function exports
-export([awaiting_hello/2, connected/2, connected/3, awaiting_peerlist/2, awaiting_pong/2]).

-include("peer.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
start_link(State) ->
    gen_fsm:start_link(p2phun_peer, State, []).

got_hello(PeerPid, PeerId) ->
    gen_fsm:send_event(PeerPid, {got_hello, PeerId}).

send_peerlist(PeerPid) ->
    gen_fsm:send_all_state_event(PeerPid, send_peerlist).

send_pong(PeerPid) ->
    gen_fsm:send_all_state_event(PeerPid, send_pong).

request_peerlist(PeerPid, CallersPid) ->
    gen_fsm:send_event(PeerPid, {request_peerlist, CallersPid}).

got_peerlist(PeerPid, Peers) ->
    gen_fsm:send_event(PeerPid, {got_peerlist, Peers}).

request_pong(PeerPid, CallersPid) ->
    gen_fsm:send_event(PeerPid, {ping, CallersPid}).

got_pong(PeerPid) ->
    gen_fsm:send_event(PeerPid, got_pong).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------
init(#peerstate{we_connected=WeConnected} = State) when WeConnected == true ->
    send_hello(State),
    {ok, awaiting_hello, State};
init(#peerstate{we_connected=WeConnected} = State) when WeConnected == false ->
    {ok, awaiting_hello, State};
init(_State) ->
    {stop, state_unparseable}.

handle_event(send_pong, StateName, State) ->
    send(pong, State),
    {next_state, StateName, State};
handle_event(send_peerlist, StateName, State) ->
    Peers = p2phun_peertable:fetch_all_servers(State#peerstate.my_id),
    send({peer_list, Peers}, State),
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, _StName, StData) ->
    {stop, unimplemented, StData}.

handle_info(_Info, _StName, StData) ->
    {stop, unimplemented, StData}.

terminate(_Reason, _StName, _StData) -> ok.

code_change(_OldVsn, StName, StData, _Extra) -> {ok, StName, StData}.

%% ------------------------------------------------------------------
%% gen_fsm State Function Definitions
%% ------------------------------------------------------------------
awaiting_hello({got_hello, #hello{id=PeerId, server_port=ListeningPort} = _Hello}, #peerstate{my_id=MyId, sock=Sock, peer_pid=PeerPid} = State) ->
    lager:info("Node-~p: Got hello from node ~p", [MyId, PeerId]),
    {ok, [{Address, Port}]} = inet:peernames(Sock),
    Peer = #peer{id=PeerId, address=Address, connection_port=Port, server_port=ListeningPort, peer_pid=PeerPid},
    p2phun_peertable:add_peers(MyId, [Peer]),
    case State#peerstate.we_connected of
      false -> send_hello(State);
      true -> ok
    end,
    {next_state, connected, State#peerstate{peer_id=PeerId}};
awaiting_hello(SomeEvent, #peerstate{my_id=MyId} = State) ->
    lager:warning("Node-~p: Say hello before doing ~p or anything else.", [MyId, SomeEvent]),
    {next_state, initializing, State}.

connected({ping, CallersPid}, State) ->
    send(ping, State),
    {next_state, awaiting_pong, State#peerstate{callers_pid=CallersPid}};
connected({request_peerlist, CallersPid}, State) ->
    send(request_peerlist, State),
    {next_state, awaiting_peerlist, State#peerstate{callers_pid=CallersPid}};
connected(_SomeEvent, State) ->
    lager:info("Saa har vi faet sagt halloej!"),
    {next_state, connected, State}.

connected(_SomeEvent, _From, State) ->
    {next_state, connected, State}.

awaiting_pong(got_pong, #peerstate{callers_pid=CallersPid} = State) ->
    CallersPid ! pong,
    {next_state, connected, State}.

awaiting_peerlist({got_peerlist, Peers}, #peerstate{callers_pid=CallersPid} = State) ->
    CallersPid ! {got_peerlist, Peers},
    {next_state, connected, State#peerstate{callers_pid=no_receiver}};
awaiting_peerlist(SomeEvent, State) ->
    lager:info("Event '~p' was not expected now. State: '~p'.", [SomeEvent, State]),
    {error, awaiting_peerlist}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
send_hello(#peerstate{my_id=MyId} = State) ->
    ListeningPort = p2phun_node_configuration:listening_port(MyId),
    HelloMsg = #hello{id=MyId, server_port=ListeningPort},
    send({hello, HelloMsg}, State).

send(Msg, #peerstate{transport=Transport, sock=Sock} = _State) ->
    Transport:send(Sock, term_to_binary(Msg)).
