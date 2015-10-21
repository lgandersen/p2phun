-module(p2phun_peer).
-behaviour(gen_fsm).

%% Api function exports
-export([start_link/1, got_hello/2, send_peerlist/1, request_peerlist/1, request_peerlist/2, got_peerlist/2, got_pong/1, ping/1, ping/2, pong/1]).

%% gen_fsm exports
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3, code_change/4]).

%% State function exports
-export([awaiting_hello/2, connected/2, connected/3, awaiting_peerlist/2, awaiting_pong/2]).

-import(p2phun_utils, [lager_info/3, lager_info/2]).
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

request_peerlist(PeerPid, CallersPid) ->
    gen_fsm:send_event(PeerPid, {request_peerlist, CallersPid}).

request_peerlist(PeerPid) ->
    gen_fsm:send_event(PeerPid, {request_peerlist, self()}),
    receive {got_peerlist, Peers} -> ok end,
    Peers.

got_peerlist(PeerPid, Peers) ->
    gen_fsm:send_event(PeerPid, {got_peerlist, Peers}).

ping(PeerPid) ->
    gen_fsm:send_event(PeerPid, {ping, self()}),
    receive pong -> ok
    after 5000 -> ping_timeout end.
ping(PeerPid, CallersPid) ->
    gen_fsm:send_event(PeerPid, {ping, CallersPid}).

pong(PeerPid) ->
    gen_fsm:send_all_state_event(PeerPid, pong).

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

handle_event(pong, StateName, State) ->
    send(pong, State),
    {next_state, StateName, State};
handle_event(send_peerlist, StateName, State) ->
    Peers = p2phun_peertable:fetch_all_servers(State#peerstate.my_id),
    send({peer_list, Peers}, State),
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, _StName, StData) ->
    {stop, unimplemented, StData}.

handle_info(_Info, _StName, StData) ->
    lager:info("Stiiill alive"),
    {stop, unimplemented, StData}.

terminate(_Reason, _StName, _StData) -> ok.

code_change(_OldVsn, StName, StData, _Extra) -> {ok, StName, StData}.

%% ------------------------------------------------------------------
%% gen_fsm State Function Definitions
%% ------------------------------------------------------------------
awaiting_hello(
    {got_hello, {#hello{id=PeerId, server_port=ListeningPort}, CallersPid}},
    #peerstate{my_id=MyId, address=Address, port=Port, peer_pid=PeerPid, connection_pid=ConnPid} = State) ->
    NotifyCaller = fun(Msg) ->
        case CallersPid of
            undefined -> ok;
            _ -> CallersPid ! Msg
        end end,
    lager_info(MyId, "Got hello from node ~p", [p2phun_utils:b64(PeerId)]),
    Peer = #peer{id=PeerId, address=Address, connection_port=Port, server_port=ListeningPort, peer_pid=PeerPid},
    case p2phun_peertable:add_peer_if_possible(MyId, Peer) of
            peer_added ->
                NotifyCaller(ok);
            FailureReason ->
                p2phun_peer_connection:close_connection(ConnPid),
                NotifyCaller(FailureReason),
                exit({FailureReason})
    end,
    case State#peerstate.we_connected of
      false -> send_hello(State);
      true -> ok
    end,
    {next_state, connected, State#peerstate{peer_id=PeerId}};
awaiting_hello(SomeEvent, #peerstate{my_id=MyId} = State) ->
    lager_info(MyId, "Say hello before doing ~p or anything else.", [SomeEvent]),
    {next_state, initializing, State}.

connected({ping, CallersPid}, State) ->
    send(ping, State),
    {next_state, awaiting_pong, State#peerstate{caller=CallersPid}};
connected({request_peerlist, CallersPid}, State) ->
    send(request_peerlist, State),
    {next_state, awaiting_peerlist, State#peerstate{caller=CallersPid}};
connected(_SomeEvent, State) ->
    {next_state, connected, State}.

connected(_SomeEvent, _From, State) ->
    {next_state, connected, State}.

awaiting_pong(got_pong, #peerstate{caller=CallersPid} = State) ->
    CallersPid ! pong,
    {next_state, connected, State}.

awaiting_peerlist({got_peerlist, Peers}, #peerstate{caller=CallersPid} = State) ->
    CallersPid ! {got_peerlist, Peers},
    {next_state, connected, State#peerstate{caller=no_receiver}};
awaiting_peerlist(SomeEvent, State) ->
    lager:error("Event '~p' was not expected now. State: '~p'.", [SomeEvent, State]),
    {error, awaiting_peerlist}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
send_hello(#peerstate{my_id=MyId} = State) ->
    ListeningPort = p2phun_node_configuration:listening_port(MyId),
    HelloMsg = #hello{id=MyId, server_port=ListeningPort},
    send({hello, HelloMsg}, State).

send(Msg, #peerstate{send=Send} = _State) ->
    Send(term_to_binary(Msg)).
