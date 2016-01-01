-module(p2phun_json_api).
-behaviour(ranch_protocol).

-include("peer.hrl").

-record(state, {sock, transport, buffer = <<>>}).

-import(p2phun_utils, [int/2, b64/1, lager_info/3, lager_info/3]).

-export([start_link/4, init/4]).

%-type state() :: {state, {sock, sock()}, {transport, transport()}, {buffer, binary()}}

-dialyzer({nowarn_function, decode_json/1}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-spec start_link(Ref :: pid(), Socket::inet:socket(), Transport::atom(), Opts::[]) -> {ok, pid()}.
start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.
 
init(Ref, Sock, Transport, _Opts = []) ->
    ok = ranch:accept_ack(Ref),
    loop(#state{sock=Sock, transport=Transport}).
 
%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
loop(#state{sock=Sock, transport=Transport, buffer=Buffer} = State) ->
    case Transport:recv(Sock, 0, 5000) of
        {ok, Data} ->
            lager:info("Wooto ~p", [Data]),
            NewState = decode_json(State#state{buffer= <<Buffer/binary, Data/binary>>}),
            loop(NewState);
        _ ->
            ok = Transport:close(Sock)
    end.

decode_json(#state{buffer=RawData} = State) ->
    try jiffy:decode(RawData, [return_trailer, return_maps]) of
        {has_trailer, EJSON, Rest} ->
            parse_json(EJSON, State),
            decode_json(State#state{buffer=Rest});
        EJSON ->
            parse_json(EJSON, State),
            State#state{buffer= <<>>}
    catch
        error:{13, invalid_string} -> State
    end.

-spec parse_json(EJSON :: #{}, State :: #state{}) -> ok | {error, any()}.
parse_json(#{
    <<"mod">> := <<"p2phun_peertable_operations">>,
    <<"fun">> := <<"fetch_all">>,
    <<"args">> := MyId}, State) ->
    Response = [
        {[{id, b64(Id)}, {address, address_to_binary(Address)}, {port, Port}]} ||
        #peer{id=Id, address=Address, server_port=Port} = _P <- p2phun_peertable_operations:fetch_all_(?ROUTINGTABLE(int(b64, MyId)))],
    lager:info("Virker det?:~p", [Response]),
    send(Response, State);
parse_json(#{
    <<"mod">> := <<"p2phun_swarm">>,
    <<"fun">> := <<"find_node">>,
    <<"args">> := [MyId, Id2Find]}, _State) ->
    lager:info("FIND NODE:"),
    case p2phun_swarm:find_node(int(b64, MyId), int(b64, Id2Find)) of
        no_node_found ->
            lager:info("WHILE TESTING: fandt ikke en skiiiid!"),
            no_node_found;
        {node_found, {NodeId, PeerPid}} ->
            lager:info("WHILE TESTING: ~p ~p", [NodeId, PeerPid])
    end;
    %send(Response, State);
parse_json(EJSON, _State) ->
    lager:info("HER ER DER SGU NOGET JSON MAAYN:~p", [EJSON]).

send(Msg, #state{transport=Transport, sock=Sock}) ->
    Resp = jiffy:encode(Msg),
    lager:info("V2222222et?:~p", [Resp]),
    Transport:send(Sock, Resp).

address_to_binary(undefined) ->
    address_to_binary(io_lib:format("~p",[undefined]));
address_to_binary(Address) ->
    binary:list_to_bin(Address).
