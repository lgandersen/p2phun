-module(p2phun_peertable).
-behaviour(gen_server).

-import(p2phun_utils, [lager_info/3, lager_info/3]).
-include("peer.hrl").

-include_lib("stdlib/include/ms_transform.hrl").

-record(state, {tablename, id, space_size, bigbin, bigbin_size, smallbins, smallbin_size}).

-ifdef(TEST).
-compile(export_all).
-else.
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/2, sudo_add_peers/2, add_peer_if_possible/2, delete_peers/2, fetch_peer/2, fetch_all/1, fetch_all_servers/2, peers_not_in_table/2, insert_if_not_exists/2]).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-endif.

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Id, RoutingTableSpec) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, RoutingTableSpec], []).

sudo_add_peers(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {sudo_add_peers, Peers}).

add_peer_if_possible(MyId, Peer) ->
    gen_server:call(?MODULE_ID(MyId), {add_peer_if_possible, Peer}).

delete_peers(MyId, Peers) ->
    gen_server:cast(?MODULE_ID(MyId), {delete_peers, Peers}).

fetch_peer(MyId, PeerId) ->
    gen_server:call(?MODULE_ID(MyId), {fetch_peer, PeerId}).

insert_if_not_exists(MyId, PeerId) ->
    gen_server:call(?MODULE_ID(MyId), {insert_if_not_exists, PeerId}).

fetch_all(MyId) ->
    gen_server:call(?MODULE_ID(MyId), fetch_all).

fetch_all_servers(MyId, TimeStamp) ->
    gen_server:call(?MODULE_ID(MyId), {fetch_all_servers, TimeStamp}).

peers_not_in_table(MyId, Peers) ->
    gen_server:call(?MODULE_ID(MyId), {peers_not_in_table, Peers}).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Id, RoutingTableSpeac]) ->
    #{smallbin_nodesize:=SmallBin_NodeSize,
    bigbin_nodesize:=BigBin_NodeSize,
    bigbin_spacesize:=BigBin_SpaceSize,
    number_of_smallbins:=NumberOfSmallBins,
    space_size:=SpaceSize} = RoutingTableSpeac,
    Tablename = p2phun_utils:id2proc_name(peers, Id),
    ets:new(Tablename, [ordered_set, named_table, {keypos, 2}]),
    SmallBins = create_intervals(BigBin_SpaceSize, SpaceSize, NumberOfSmallBins),
    {ok, #state{
        id=Id,
        tablename=Tablename,
        space_size=SpaceSize,
        bigbin={-1, BigBin_SpaceSize}, % -1 s.t. own key will fall within this bin as well
        bigbin_size=BigBin_NodeSize,
        smallbins=SmallBins,
        smallbin_size=SmallBin_NodeSize
        }}.

handle_call({fetch_peer, PeerId}, _From, State) ->
    {reply, fetch_peer_(PeerId, State), State};
handle_call({insert_if_not_exists, PeerId}, _From, State) ->
    {reply, insert_if_not_exists_(PeerId, State), State};
handle_call({add_peer_if_possible, Peer}, _From, State) ->
    {reply, add_peer_if_possible_(Peer, State), State};
handle_call(fetch_all, _From, State) ->
    {reply, fetch_all_(State), State};
handle_call({fetch_all_servers, TimeStamp}, _From, State) ->
    {reply, fetch_all_servers_(TimeStamp, State), State};
handle_call({peers_not_in_table, Peers}, _From, State) ->
    {reply, peers_not_in_table_(Peers, State), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({sudo_add_peers, Peers}, State) ->
    sudo_add_peers_(Peers, State),
    {noreply, State};
handle_cast({delete_peers, Peers}, State) ->
    delete_peers_(Peers, State),
    {noreply, State};
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
add_peer_if_possible_(Peer, S) ->
    case peer_already_in_table(Peer, S) of
        true ->
            already_in_table;
        false ->
            case room_for_peer(Peer, S) of
                yes ->
                    sudo_add_peers_([Peer], S),
                    peer_added;
                Failure -> Failure
            end
    end.

peer_already_in_table(Peer, S) ->
    case fetch_peer_(Peer#peer.id, S) of
        [] -> false;
        _ -> true
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

sudo_add_peers_(Peers, S) ->
    ets:insert(S#state.tablename, Peers).

delete_peers_(Peers, S) ->
    lists:foreach(fun(Peer) -> ets:delete(S#state.tablename, Peer) end, Peers).

fetch_all_(S) ->
    [Peer || [Peer] <- ets:match(S#state.tablename, '$1')].

fetch_all_servers_(TimeStamp, S) ->
    MatchSpec = ets:fun2ms(fun(#peer{server_port=Port, time_added=TimeAdded} = Peer) when (Port =/= none), (TimeAdded > TimeStamp) -> Peer end),
    [Peer || Peer <- ets:select(S#state.tablename, MatchSpec)].

fetch_peer_(PeerId, S) ->
    ets:lookup(S#state.tablename, PeerId).

insert_if_not_exists_(PeerId, S) ->
    case fetch_peer_(PeerId, S) of
        [] -> 
            sudo_add_peers_([#peer{id=PeerId}], S),
            peer_inserted;
        _ ->
            peer_exists
    end.

peers_not_in_table_(Peers, S) ->
    lists:filter(
        fun(#peer{id=Id} = _Peer) ->
            case fetch_peer_(Id, S) of
                [] -> true;
                _ -> false
            end
        end, Peers).

peers_in_bin({Start, End}, #state{id=MyId, tablename=Tablename}) ->
    ets:foldl(
        fun(#peer{id=Id} = Peer, Acc) ->
            Dist = distance(MyId, Id),
            if
              (Dist > Start) and (Dist < End) -> [Peer|Acc];
              true -> Acc
            end
        end, [], Tablename).

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
