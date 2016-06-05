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
    <<"mod">> := RawMod,
    <<"fun">> := RawFun,
    <<"args">> := RawArgs}, State) ->
    Mod = binary_to_atom(RawMod, utf8),
    Fun = binary_to_atom(RawFun, utf8),
    Args = parse_args(Mod, Fun, RawArgs),
    Response = erlang:apply(Mod, Fun, Args),
    Response2 = parse_response(Mod, Fun, Response),
    send(Response2, State);
parse_json(EJSON, _State) ->
    lager:info("Json input not understood:~p", [EJSON]).

parse_args(p2phun_node_sup, create_node, [NodeCfgRaw]) ->
    NodeCfg = map_stringkeys_to_atoms(NodeCfgRaw),
    RoutingTableCfgRaw = maps:get(routingtable_cfg, NodeCfg),
    RoutingTableCfg = map_stringkeys_to_atoms(RoutingTableCfgRaw),
    [NodeCfg#{routingtable_cfg => RoutingTableCfg}];
parse_args(p2phun_peertable_operations, fetch_all, [MyId]) ->
    [int(b64, MyId)]; %perhaps list should be part of input?
parse_args(p2phun_swarm, find_node, [MyId, Id2Find]) ->
    [int(b64, MyId), int(b64, Id2Find)];
parse_args(Mod, Fun, Args) ->
    lager:info("Did not recognize combination of module, fun, args: ~p, ~p, ~p", [Mod, Fun, Args]).

map_stringkeys_to_atoms(Map) when is_map(Map) ->
    map_stringkeys_to_atoms(maps:to_list(Map), []).

map_stringkeys_to_atoms([{Key, Value} | RestMapList], NewMapList) when is_binary(Key) ->
    map_stringkeys_to_atoms(RestMapList, [{binary_to_atom(Key, utf8), Value} | NewMapList]);
map_stringkeys_to_atoms([KeyVal | RestMapList], NewMapList) ->
    map_stringkeys_to_atoms(RestMapList, [KeyVal | NewMapList]);
map_stringkeys_to_atoms([], NewMapList) ->
    maps:from_list(NewMapList).

parse_response(p2phun_node_sup, create_node, {ok, Pid}) ->
    erlang:list_to_binary(erlang:pid_to_list(Pid));
parse_response(p2phun_peertable_operations, fetch_all, Peers) ->
    [#{id => Id, address => address_to_binary(Address), port => Port} ||
    #peer{id=Id, address=Address, server_port=Port} <- Peers];
parse_response(p2phun_swarm, find_node, no_node_found) ->
    no_node_found;
parse_response(p2phun_swarm, find_node, {node_found, PeerPid}) ->
    lager:info("WHILE TESTING: ~p", [PeerPid]);
parse_response(Mod, Fun, Result) ->
    lager:info("Did not recognize result from module, fun, args: ~p, ~p, ~p", [Mod, Fun, Result]),
    error.

send(Msg, #state{transport=Transport, sock=Sock}) ->
    Resp = jiffy:encode(Msg),
    Transport:send(Sock, Resp).

address_to_binary(undefined) ->
    address_to_binary(io_lib:format("~p",[undefined]));
address_to_binary(Address) ->
    binary:list_to_bin(Address).
