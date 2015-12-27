-module(p2phun_peertable_operations).
-include("peer.hrl").

-export([
    delete_peers_/2,
    insert_if_not_exists_/2,
    fetch_all_/1,
    fetch_all_peers_to_ping_/2,
    fetch_all_peers_to_ask_for_peers_/2,
    fetch_all_servers_/2,
    fetch_peer_/2,
    fetch_last_fetched_peer_/2,
    fetch_peers_closest_to_id_/4,
    fetch_peers_closest_to_id_and_not_processed/4,
    peer_already_in_table_/2,
    peers_not_in_table_/2,
    sudo_add_peers_/2,
    update_peer_/3]).


-spec fetch_all_(Table :: table()) -> [#peer{}].
fetch_all_(Table) -> [Peer || [Peer] <- ets:match(Table, '$1')].

-spec fetch_peer_(Table :: table(), PeerId :: id()) -> [#peer{}].
fetch_peer_(Table, PeerId) -> ets:lookup(Table, PeerId).

-spec sudo_add_peers_(Table :: table(), Peers :: [#peer{}]) -> true.
sudo_add_peers_(_Table, []) -> true;
sudo_add_peers_(Table, Peers) -> ets:insert(Table, Peers).

-spec delete_peers_(Peers :: [id()], Table :: table()) -> ok.
delete_peers_(Peers, Table) ->
    lists:foreach(fun(Peer) -> ets:delete(Table, Peer) end, Peers).

-spec fetch_all_peers_to_ask_for_peers_(Table :: table(), MaxTimeSinceLastSpoke :: integer()) -> [#peer{}].
fetch_all_peers_to_ask_for_peers_(Table, MaxTimeSinceLastRequest) ->
    Now = erlang:system_time(milli_seconds),
    MatchSpec = ets:fun2ms(
        fun(#peer{pid=PeerPid, last_peerlist_request=LastRequest} = _Peer) when (Now - LastRequest > MaxTimeSinceLastRequest) -> PeerPid end),
    ets:select(Table, MatchSpec).

-spec fetch_all_peers_to_ping_(Table :: table(), MaxTimeSinceLastSpoke :: integer()) -> [#peer{}].
fetch_all_peers_to_ping_(Table, MaxTimeSinceLastSpoke) ->
    Now = erlang:system_time(milli_seconds),
    MatchSpec = ets:fun2ms(
        fun(#peer{pid=PeerPid, last_spoke=LastSpoke} = _Peer) when (Now - LastSpoke > MaxTimeSinceLastSpoke) -> PeerPid end),
    ets:select(Table, MatchSpec).

-spec fetch_last_fetched_peer_(Table :: table(), PeerId :: id()) -> integer().
fetch_last_fetched_peer_(Table, PeerId) ->
    [Peer] = ets:lookup(Table, PeerId),
    Peer#peer.last_fetched_peer.

-spec fetch_peers_closest_to_id_and_not_processed(Table :: table(), Id :: id(), MaxDist :: integer(), MaxVals :: non_neg_integer()) -> [#peer{}].
fetch_peers_closest_to_id_and_not_processed(Table, Id, MaxDist, MaxVals) ->
    MatchSpec = ets:fun2ms(
        fun(#peer{id=PeerId, address=Address, server_port=Port, processed=Processed} = _Peer) when (PeerId bxor Id < MaxDist), Processed =:= false ->
            #peer{id=PeerId, address=Address, server_port=Port} end),
    fetch_peers_closest_to_id_1(Table, Id, MaxVals, MatchSpec).

-spec fetch_peers_closest_to_id_(Table :: table(), Id :: id(), MaxDist :: integer(), MaxVals :: non_neg_integer()) -> [#peer{}].
fetch_peers_closest_to_id_(Table, Id, MaxDist, MaxVals) ->
    MatchSpec = ets:fun2ms(
        fun(#peer{id=PeerId, address=Address, server_port=Port} = _Peer) when (PeerId bxor Id < MaxDist) ->
            #peer{id=PeerId, address=Address, server_port=Port} end),
    fetch_peers_closest_to_id_1(Table, Id, MaxVals, MatchSpec).

-spec fetch_peers_closest_to_id_1(Table :: table(), Id :: id(), MaxVals :: non_neg_integer(), MatchSpec :: ets:match_spec()) -> [#peer{}].
fetch_peers_closest_to_id_1(Table, Id, MaxVals, MatchSpec) ->
    Sorter = fun(Peer1, Peer2) -> Peer1#peer.id bxor Id < Peer2#peer.id bxor Id end,
    FormatList = fun(Peers) -> lists:sublist(lists:sort(Sorter, Peers), MaxVals) end,
    fetch_peers_closest_to_id_2(ets:select(Table, MatchSpec, ?MAX_TABLE_FETCH), [], FormatList).

-spec fetch_peers_closest_to_id_2(
    Progress :: '$end_of_table' | {[#peer{}], ets:continuation()},
    Results :: [#peer{}],
    FormatList :: fun(([#peer{}]) -> [#peer{}])
    ) -> [#peer{}].
fetch_peers_closest_to_id_2('$end_of_table', Results, FormatList) -> FormatList(Results);
fetch_peers_closest_to_id_2({NextResult, Continuation}, ResultsSoFar, FormatList) ->
    fetch_peers_closest_to_id_2(ets:select(Continuation), FormatList(NextResult ++ ResultsSoFar), FormatList).

-spec peer_already_in_table_(Peer :: #peer{}, Table :: table()) -> true | false.
peer_already_in_table_(Peer, Table) ->
    case fetch_peer_(Table, Peer#peer.id) of
        [] -> false;
        _ -> true
    end.

-spec update_peer_(Table :: table(), PeerId :: id(), Updates :: [{atom(), term()}]) -> true.
update_peer_(Table, PeerId, Updates) ->
    UpdatesMap = maps:from_list(Updates),
    Fields = record_info(fields, peer),
    [Peer] = fetch_peer_(Table, PeerId),
    [peer|Values] = tuple_to_list(Peer),
    UpdatedValues = lists:map(
        fun(Field) -> updating_peer__(Field, UpdatesMap) end,
        lists:zip(Fields, Values)),
    sudo_add_peers_(Table, [list_to_tuple([peer | UpdatedValues])]).

-spec updating_peer__(NameAndValue :: {atom(), term()}, Update :: #{}) -> any().
updating_peer__({FieldName, FieldValue}, Update) ->
    case maps:is_key(FieldName, Update) of
        true -> maps:get(FieldName, Update);
        false -> FieldValue
    end.

-spec fetch_all_servers_(TimeStamp :: integer(), Table :: table()) -> [#peer{}].
fetch_all_servers_(TimeStamp, Table) ->
    MatchSpec = ets:fun2ms(fun(#peer{server_port=Port, time_added=TimeAdded} = Peer) when (Port =/= none), (TimeAdded > TimeStamp) -> Peer end),
    [Peer || Peer <- ets:select(Table, MatchSpec)].

-spec insert_if_not_exists_(id(), table()) -> peer_inserted | peer_exists.
insert_if_not_exists_(PeerId, Table) ->
    case fetch_peer_(Table, PeerId) of
        [] -> 
            sudo_add_peers_(Table, [#peer{id=PeerId}]),
            peer_inserted;
        _ ->
            peer_exists
    end.

-spec peers_not_in_table_(table(), [#peer{}]) -> [true | false].
peers_not_in_table_(Table, Peers) ->
    lists:filter(
        fun(#peer{id=Id} = _Peer) ->
            case fetch_peer_(Table, Id) of
                [] -> true;
                _ -> false
            end
        end, Peers).
