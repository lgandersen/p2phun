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

-export([peermanager/2]).
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
    StateFsm = #peerstate{
        my_id=MyId,
        we_connected=false,
        port=Port,
        address=Address,
        sock=Sock,
        transport=Transport},
    {ok, FsmPid} = p2phun_peerstate:start_link(StateFsm),
    State = StateFsm#peerstate{fsm_pid=FsmPid},
    ok = Transport:setopts(Sock, [binary, {packet, 4}, {active, once}]),
    ok = ranch:accept_ack(Ref),
    gen_server:enter_loop(?MODULE, [], State).


%% We connect
init([Address, Port, MyId]) ->
    case gen_tcp:connect(Address, Port, [binary, {packet, 4}, {active, once}], 10000) of
        {ok, Sock} -> 
            StateFsm = #peerstate{
                my_id=MyId,
                we_connected=true,
                sock=Sock,
                address=Address,
                port=Port,
                transport=gen_tcp},
            {ok, FsmPid} = p2phun_peerstate:start_link(StateFsm),
            State = StateFsm#peerstate{fsm_pid=FsmPid},
            lager:info("Id ~p successly connected to peer at port ~p", [MyId, Port]),
            {ok, State};
        {error, Reason} ->
            {stop, {connection_error, Reason}}
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({tcp, Sock, RawData}, #peerstate{my_id=MyId, sock=Sock, fsm_pid=FsmPid, port=Port} = State) ->
    case binary_to_term(RawData) of
        ping ->
            p2phun_peerstate:got_pong(FsmPid),
            NewState = State;
        {hello, {id, PeerId}} ->
            lager:info("Node-~p: Hello from node ~p on port ~p.", [MyId, PeerId, Port]),
            p2phun_peerstate:got_hello(FsmPid, PeerId),
            % Make check here to verify that we are not already connected to this node!
            name_me(MyId, PeerId),
            NewState = State#peerstate{peer_id=PeerId},
            spawn_link(?MODULE, peermanager, [0, NewState]);
       {request_peerlist} ->
            lager:info("Peer request !!!! to ~p from ~p", [MyId, Port]),
            p2phun_peerstate:send_peerlist(FsmPid),
            NewState = State;
       {peer_list, Peers} ->
            p2phun_peerstate:got_peerlist(FsmPid, Peers),
            NewState = State;
        Other ->
            lager:error("Could not parse input: ~p", [Other]),
            NewState = State
    end,
    inet:setopts(Sock, [{active, once}]),
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
name_me(MyId, PeerId) ->
    register(p2phun_utils:peer_process_name(MyId, PeerId), self()).

%% THIS SHOULD BE FACTORED OUT TO A SEPERATE MODULE
% Here we should do simple repeating tasks like fetching of peer information etc.
peermanager(Count, #peerstate{my_id=MyId, fsm_pid=FsmPid} = State) ->
    timer:sleep(1000),
    case Count > 1 of
        true ->
            p2phun_peerstate:request_peerlist(FsmPid, self()),
            %request_peerlist(self(), MyId, PeerId),
            receive
                {got_peerlist, Peers} -> ok
            end,
            p2phun_peertable:add_and_return_peers_not_in_table(MyId, Peers),
            NewCount = 0;
        false ->
            NewCount = Count + 1
    end,
    timer:sleep(1000),
    p2phun_peerstate:ping(FsmPid, self()),
    peermanager(NewCount, State).
