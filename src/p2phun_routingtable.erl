-module(p2phun_routingtable).
-behaviour(gen_server).

-include("peer.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-import(p2phun_utils, [lager_info/3, lager_info/3]).

-import(p2phun_peertable_operations, [
    peer_already_in_table_/2,
    sudo_add_peers_/2,
    update_peer_/3,
    delete_peers_/2
    ]).


-ifdef(TEST).
-compile(export_all).
-else.
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/3, server_port/1, update_timestamps/3, add_peer_if_possible/2, delete_peers/2]).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%%  ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-endif.

-type routing_table_config() :: [
    {space_size, pos_integer()} |
    {bigbin_spacesize, pos_integer()} |
    {number_of_smallbins, pos_integer()} |
    {smallbin_nodesize, pos_integer()} |
    {bigbin_nodesize, pos_integer()}
    ].
-type bin() :: {non_neg_integer(), non_neg_integer()}.

-type add_peer_result() :: peer_added | already_in_table | table_full.

-record(state, {table, id, server_port, space_size, bigbin, bigbin_size, smallbins, smallbin_size}).
%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-spec start_link(
    Id :: id(),
    RoutingTableSpec :: routing_table_config(),
    ServerPort :: inet:port_number()) ->
    {ok, pid()} | ignore | {error, error()}.
start_link(Id, RoutingTableSpec, ServerPort) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, RoutingTableSpec, ServerPort], []).

-spec server_port(id()) -> inet:port_number().
server_port(Id) ->
    gen_server:call(?MODULE_ID(Id), server_port).

-spec add_peer_if_possible(id(), #peer{}) -> add_peer_result().
add_peer_if_possible(MyId, Peer) ->
    gen_server:call(?MODULE_ID(MyId), {add_peer_if_possible, Peer}).

-spec delete_peers(id(), [id()]) -> ok.
delete_peers(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {delete_peers, Peers}).

-spec update_timestamps(MyId::id(), PeerId::id(), Peers::[#peer{}]) -> ok.
update_timestamps(MyId, PeerId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {update_peer, PeerId, Peers}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Id, RoutingTableSpec, ServerPort]) ->
    #{smallbin_nodesize:=SmallBin_NodeSize,
    bigbin_nodesize:=BigBin_NodeSize,
    bigbin_spacesize:=BigBin_SpaceSize,
    number_of_smallbins:=NumberOfSmallBins,
    space_size:=SpaceSize} = RoutingTableSpec,
    ets:new(?ROUTINGTABLE(Id), [set, named_table, {keypos, 2}]),
    SmallBins = create_intervals(BigBin_SpaceSize, SpaceSize, NumberOfSmallBins),
    {ok, #state{
        id=Id,
        server_port=ServerPort,
        table=?ROUTINGTABLE(Id),
        space_size=SpaceSize,
        bigbin={-1, BigBin_SpaceSize}, % -1 s.t. own key will fall within this bin as well
        bigbin_size=BigBin_NodeSize,
        smallbins=SmallBins,
        smallbin_size=SmallBin_NodeSize
        }}.

handle_call(server_port, _From, State) ->
    {reply, State#state.server_port, State};
handle_call({add_peer_if_possible, Peer}, _From, State) ->
    {reply, add_peer_if_possible_(Peer, State), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({delete_peers, Peers}, #state{table=Table} = State) ->
    delete_peers_(Peers, Table),
    {noreply, State};
handle_cast({update_peer, PeerId, Peers}, #state{table=Table} = State) ->
    update_timestamps_(Peers,  PeerId, Table),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec update_timestamps_(Peers :: [], PeerId :: id(), Table :: table()) -> true.
update_timestamps_([],  PeerId, Table) ->
    update_peer_(Table, PeerId, [
        {last_peerlist_request, erlang:system_time(milli_seconds)},
        {last_spoke, erlang:system_time(milli_seconds)}
        ]);
update_timestamps_(Peers, PeerId, Table) ->
    update_peer_(Table, PeerId, [
        {last_peerlist_request, erlang:system_time(milli_seconds)},
        {last_spoke, erlang:system_time(milli_seconds)},
        {last_fetched_peer, lists:max([Peer#peer.time_added || Peer <- Peers])}
        ]).

-spec add_peer_if_possible_(#peer{}, #state{}) -> add_peer_result().
add_peer_if_possible_(Peer, #state{table=Table} = S) ->
    case peer_already_in_table_(Peer, Table) of
        true ->
            already_in_table;
        false ->
            case room_for_peer(Peer, S) of
                true ->
                    sudo_add_peers_(Table, [Peer]),
                    peer_added;
                false -> table_full
            end
    end.

-spec room_for_peer(Peer :: peer(), State :: #state{}) -> true | false.
room_for_peer(#peer{id=Id}, #state{id=MyId, bigbin_size=BigBin_Size, smallbin_size=SmallBin_Size} = S) ->
    {Start, End} = bin_of_peer(distance(Id, MyId), S),
    NumPeersInBin = length(peers_in_bin({Start, End}, S)),
    if
        ((Start > -1) and (NumPeersInBin < SmallBin_Size)) or
        ((Start == -1) and (NumPeersInBin < BigBin_Size)) ->
            true;
        true ->
            false
    end.

-spec peers_in_bin(Bin :: bin(), State :: #state{}) -> [peer()].
peers_in_bin({Start, End}, #state{id=MyId} = _S) ->
    ets:foldl(
        fun(#peer{id=Id} = Peer, Acc) ->
            Dist = distance(MyId, Id),
            if
              (Dist > Start) and (Dist < End) -> [Peer|Acc];
              true -> Acc
            end
        end, [], ?ROUTINGTABLE(MyId)).

-spec bin_of_peer(DistToPeer :: pos_integer(), #state{}) -> bin().
bin_of_peer(DistToPeer, #state{bigbin=BigBin, smallbins=SmallBins}) ->
    [Bin] = lists:filter(
        fun({Start, End}) -> (Start < DistToPeer) and (DistToPeer =< End) end,
        [BigBin|SmallBins]),
    Bin.

-spec create_intervals(
    Start :: non_neg_integer(), End :: non_neg_integer(), NumberOfBins :: pos_integer()) -> [bin()].
create_intervals(Start, End, NumberOfBins) ->
    IntervalSequence = create_interval_sequence(Start, End, NumberOfBins),
    create_intervals_(IntervalSequence, []).

-spec create_intervals_(IntervalSeq :: [non_neg_integer()], Intervals :: [bin()]) -> [bin()].
create_intervals_([Start,End|T], Intervals) -> 
    create_intervals_([End|T], [{Start, End}|Intervals]);
create_intervals_([_Last], Intervals) -> lists:reverse(Intervals).

-spec create_interval_sequence(Start::non_neg_integer(), End::non_neg_integer(), NumberOfBins::pos_integer()) -> [non_neg_integer()].
create_interval_sequence(Start, End, NumberOfBins) ->
    Length = End - Start,
    Step = p2phun_utils:floor(Length / NumberOfBins),
    Rest = Length rem Step,
    create_interval_sequence_(Step, End, Rest, [Start]).

-spec create_interval_sequence_(
    Step::pos_integer(), End::non_neg_integer(), Rest::non_neg_integer(), Points::[non_neg_integer()]) ->
    [non_neg_integer()].
create_interval_sequence_(Step, End, Rest, [LastPoint|T]) when Step + LastPoint < End ->
    case Rest > 0 of
        true -> create_interval_sequence_(Step, End, Rest - 1, [LastPoint + Step + 1, LastPoint|T]);
        false -> create_interval_sequence_(Step, End, 0, [LastPoint + Step, LastPoint|T])
    end;
create_interval_sequence_(_Step, End, 0, Points) ->
    lists:reverse([End|Points]).

-spec distance(id(), id()) -> non_neg_integer().
distance(Id1, Id2) -> Id1 bxor Id2.
