-module(p2phun_json_api).
-behaviour(ranch_protocol).

-include("peer.hrl").

-record(state, {sock, transport, buffer = <<>>}).

-export([start_link/4, init/4]).


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
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
            loop(decode_json(State#state{buffer= <<Buffer/binary, Data/binary>>}));
        _ ->
            ok = Transport:close(Sock)
    end.

decode_json(#state{buffer=RawData} = State) ->
    try jiffy:decode(RawData, [return_trailer]) of
        {has_trailer, EJSON, Rest} ->
            parse_json(EJSON),
            State#state{buffer=Rest};
        EJSON ->
            parse_json(EJSON),
            State#state{buffer= <<>>}
    catch
        error:{13, invalid_string} -> State
    end.

parse_json(EJSON) ->
    lager:info("HER ER DER SGU NOGET JSON MAAYN:~p", [EJSON]).
