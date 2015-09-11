-module(p2phun_peer_connection).
-behaviour(gen_server).
-behaviour(ranch_protocol).
-include("peer.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
%% Startup

-export([start_link/4, start_link/3]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, init/4, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [Ref, Socket, Transport, Opts]).

start_link(Address, Port, Opts) ->
    gen_server:start_link(?MODULE, [Address, Port, Opts], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

%% They connect
init(Ref, Sock, Transport, [MyId] = _Opts) ->
    ok = proc_lib:init_ack({ok, self()}),
    %% Perform any required state initialization here.
    {ok, [{Address, Port}]} = inet:peernames(Sock),
    State = initialize(MyId, Address, Port, Sock, Transport, false),
    ok = Transport:setopts(Sock, [binary, {packet, 4}, {active, once}]),
    ok = ranch:accept_ack(Ref),
    gen_server:enter_loop(?MODULE, [], State).


%% We connect
init([Address, Port, MyId]) ->
    case gen_tcp:connect(Address, Port, [binary, {packet, 4}, {active, once}], 10000) of
        {ok, Sock} -> 
            State = initialize(MyId, Address, Port, Sock, gen_tcp, true),
            lager:info("Id ~p successly connected to peer at port ~p", [MyId, Port]),
            {ok, State};
        {error, Reason} ->
            {stop, {connection_error, Reason}}
    end.

initialize(MyId, Address, Port, Sock, Transport, WeConnected) ->
    PeerState= #peerstate{
        my_id=MyId,
        we_connected=WeConnected,
        sock=Sock,
        address=Address,
        port=Port,
        transport=Transport},
    {ok, PeerPid} = p2phun_peer:start_link(PeerState),
    PeerState#peerstate{peer_pid=PeerPid}.


handle_call(_Request, _From, State) ->
    {reply, ok, State}.
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({tcp, Sock, RawData}, #peerstate{my_id=MyId, sock=Sock, peer_pid=PeerPid, port=Port} = State) ->
    case binary_to_term(RawData) of
        ping ->
            p2phun_peer:got_pong(PeerPid),
            NewState = State;
        {hello, {id, PeerId}} ->
            lager:info("Node-~p: Hello from node ~p on port ~p.", [MyId, PeerId, Port]),
            p2phun_peer:got_hello(PeerPid, PeerId),
            % Make check here to verify that we are not already connected to this node!
            name_me(MyId, PeerId),
            NewState = State#peerstate{peer_id=PeerId},
            spawn_link(p2phun_peer_manager, init, [0, NewState]);
       {request_peerlist} ->
            lager:info("Peer request !!!! to ~p from ~p", [MyId, Port]),
            p2phun_peer:send_peerlist(PeerPid),
            NewState = State;
       {peer_list, Peers} ->
            p2phun_peer:got_peerlist(PeerPid, Peers),
            NewState = State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]),
            NewState = State
    end,
    inet:setopts(Sock, [{active, once}]),
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
name_me(MyId, PeerId) -> register(p2phun_utils:peer_process_name(MyId, PeerId), self()).
