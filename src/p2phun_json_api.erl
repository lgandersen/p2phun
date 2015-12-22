-module(p2phun_json_api).
-behaviour(ranch_protocol).

-include("peer.hrl").

-record(state, {sock, transport, buffer = <<>>}).

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
parse_json(#{<<"fun">> := <<"fetch_all">>, <<"args">> := MyId}, State) ->
    Response = [
        {[{id, P#peer.id}, {address, address_to_binary(P#peer.address)}, {port, P#peer.server_port}]} ||
        P <- p2phun_peertable:fetch_all(MyId)],
    lager:info("Virker det?:~p", [Response]),
    send(Response, State);
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
