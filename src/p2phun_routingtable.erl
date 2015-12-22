-module(p2phun_routingtable).
-behaviour(gen_server).

-include("peer.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-import(p2phun_utils, [lager_info/3, lager_info/3]).

-import(p2phun_peertable_operations, [
    peer_already_in_table_/2,
    sudo_add_peers_/2
    ]).

-record(state, {tablename, id, server_port, space_size, bigbin, bigbin_size, smallbins, smallbin_size}).

-ifdef(TEST).
-compile(export_all).
-else.
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/3, server_port/1, add_peer_if_possible/2]).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-endif.

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Id, RoutingTableSpec, ServerPort) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, RoutingTableSpec, ServerPort], []).

server_port(Id) ->
    gen_server:call(?MODULE_ID(Id), server_port).

add_peer_if_possible(MyId, Peer) ->
    gen_server:call(?MODULE_ID(MyId), {add_peer_if_possible, Peer}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Id, RoutingTableSpeac, ServerPort]) ->
    #{smallbin_nodesize:=SmallBin_NodeSize,
    bigbin_nodesize:=BigBin_NodeSize,
    bigbin_spacesize:=BigBin_SpaceSize,
    number_of_smallbins:=NumberOfSmallBins,
    space_size:=SpaceSize} = RoutingTableSpeac,
    ets:new(?ROUTINGTABLE(Id), [set, named_table, {keypos, 2}]),
    SmallBins = create_intervals(BigBin_SpaceSize, SpaceSize, NumberOfSmallBins),
    {ok, #state{
        id=Id,
        server_port=ServerPort,
        tablename=?ROUTINGTABLE(Id),
        space_size=SpaceSize,
        bigbin={-1, BigBin_SpaceSize}, % -1 s.t. own key will fall within this bin as well
        bigbin_size=BigBin_NodeSize,
        smallbins=SmallBins,
        smallbin_size=SmallBin_NodeSize
        }}.

handle_call(server_port, _From, State) ->
    {reply, State#state.server_port, State};
handle_call({add_peer_if_possible, Peer}, _From, State) ->
    {reply, add_peer_if_possible_(Peer, State#state.tablename), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
add_peer_if_possible_(Peer, #state{tablename=Table} = S) ->
    case peer_already_in_table_(Peer, Table) of
        true ->
            already_in_table;
        false ->
            case room_for_peer(Peer, S) of
                yes ->
                    sudo_add_peers_([Peer], Table),
                    peer_added;
                Failure -> Failure
            end
    end.

room_for_peer(#peer{id=Id}, #state{id=MyId, bigbin_size=BigBin_Size, smallbin_size=SmallBin_Size} = S) ->
    {Start, End} = bin_of_peer(distance(Id, MyId), S),
    NumPeersInBin = length(peers_in_bin({Start, End}, S)),
    if
        ((Start > -1) and (NumPeersInBin < SmallBin_Size)) or
        ((Start == -1) and (NumPeersInBin < BigBin_Size)) ->
            yes;
        true ->
            bin_full
    end.

peers_in_bin({Start, End}, #state{id=MyId} = _S) ->
    ets:foldl(
        fun(#peer{id=Id} = Peer, Acc) ->
            Dist = distance(MyId, Id),
            if
              (Dist > Start) and (Dist < End) -> [Peer|Acc];
              true -> Acc
            end
        end, [], ?ROUTINGTABLE(MyId)).

bin_of_peer(DistToPeer, #state{bigbin=BigBin, smallbins=SmallBins}) ->
    [Bin] = lists:filter(
        fun({Start, End}) -> (Start < DistToPeer) and (DistToPeer =< End) end,
        [BigBin|SmallBins]),
    Bin.

create_intervals(Start, End, NumberOfBins) ->
    IntervalSequence = create_interval_sequence(Start, End, NumberOfBins),
    create_intervals_(IntervalSequence, []).

create_intervals_([Start,End|T], Intervals) -> 
    create_intervals_([End|T], [{Start, End}|Intervals]);
create_intervals_([_Last], Intervals) -> lists:reverse(Intervals).

create_interval_sequence(Start, End, NumberOfBins) ->
    Length = End - Start,
    Step = p2phun_utils:floor(Length / NumberOfBins),
    Rest = Length rem Step,
    create_interval_sequence_(Step, End, Rest, [Start]).

create_interval_sequence_(Step, End, Rest, [LastKnot|T] = _Knots) when Step + LastKnot < End ->
    case Rest > 0 of
        true -> create_interval_sequence_(Step, End, Rest - 1, [LastKnot + Step + 1, LastKnot|T]);
        false -> create_interval_sequence_(Step, End, 0, [LastKnot + Step, LastKnot|T])
    end;
create_interval_sequence_(_Step, End, 0, Knots) ->
    lists:reverse([End|Knots]).

distance(Id1, Id2) -> Id1 bxor Id2.
