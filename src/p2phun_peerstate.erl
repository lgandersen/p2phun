-module(p2phun_peerstate).
-behaviour(gen_fsm).

-export([start_link/1, got_hello/2, send_peerlist/1, request_peerlist/1, got_peerlist/2]).
-export([init/1, handle_event/3, awaiting_hello/2, connected/2, connected/3, awaiting_peerlist/2]).

-include("peer.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
start_link(State) ->
    gen_fsm:start_link(p2phun_peerstate, State, []).

got_hello(FsmPid, PeerId) ->
    gen_fsm:send_event(FsmPid, {got_hello, PeerId}).

send_peerlist(FsmPid) ->
    gen_fsm:send_all_state_event(FsmPid, send_peerlist).

request_peerlist({FsmPid, CallersPid}) ->
    gen_fsm:sync_send_event(FsmPid, {request_peerlist, CallersPid}).

got_peerlist(FsmPid, Peers) ->
    gen_fsm:send_event(FsmPid, {got_peerlist, Peers}).

%% State functions
init(#peerstate{we_connected=WeConnected, my_id=MyId} = State) when WeConnected == true ->
    send({hello, {id, MyId}}, State),
    {ok, awaiting_hello, State};
init(#peerstate{we_connected=WeConnected} = State) when WeConnected == false ->
    {ok, awaiting_hello, State};
init(State) ->
    lager:error("Could not initialize peerstate because faulty state supplied: ~p", [State]),
    {stop, state_unparseable}.


handle_event(send_peerlist, StateName, State) ->
    Peers = p2phun_peertable:fetch_all(State#peerstate.my_id),
    send({peer_list, Peers}, State),
    {next_state, StateName, State}.   

awaiting_hello({got_hello, PeerId}, #peerstate{my_id=MyId, sock=Sock} = State) ->
    {ok, [{Address, Port}]} = inet:peernames(Sock),
    p2phun_peertable:add_peers(MyId, {PeerId, Address, Port}),
    case State#peerstate.we_connected of
      false -> send({hello, {id, MyId}}, State);
      true -> ok
    end,
    {next_state, connected, State#peerstate{peer_id=PeerId}};
awaiting_hello(SomeEvent, #peerstate{my_id=MyId} = State) ->
    lager:warning("Node-~p: Say hello before doing ~p or anything else.", [MyId, SomeEvent]),
    {next_state, initializing, State}.    


connected(_SomeEvent, State) ->
    lager:info("Saa har vi faet sagt halloej!"),
    {next_state, connected, State}.
%% Sync
connected({request_peerlist, CallersPid}, _From, #peerstate{my_id=MyId, sock=Sock} = State) ->
    lager:info("Saa sender vi sgu en reqeust for peerlisten!"),
    send({request_peerlist}, State),
    {reply, CallersPid, awaiting_peerlist, State#peerstate{response_receiver_pid=CallersPid}};
connected(_SomeEvent, _From, State) ->
    lager:info("W000th!"),
    {next_state, connected, State}.


awaiting_peerlist({got_peerlist, Peers}, #peerstate{response_receiver_pid=CallersPid} = State) ->
    CallersPid ! {got_peerlist, Peers},
    {next_state, connected, State#peerstate{response_receiver_pid=no_receiver}};
awaiting_peerlist(SomeEvent, State) ->
    lager:info("Event '~p' was not expected now. State: '~p'.", [SomeEvent, State]),
    {error, awaiting_peerlist}.

send(Msg, #peerstate{transport=Transport, sock=Sock} = _State) ->
    Transport:send(Sock, term_to_binary(Msg)).
