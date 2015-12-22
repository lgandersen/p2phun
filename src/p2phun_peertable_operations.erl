-module(p2phun_peertable_operations).
-include("peer.hrl").

-export(p2phun_peertable_operations, [
    delete_peers_/2],
    insert_if_not_exists_/2,
    fetch_all_/1,
    fetch_all_peers_to_ping_/2,
    fetch_all_peers_to_ask_for_peers_/2,
    fetch_all_servers_/2,
    fetch_peer_/2,
    fetch_last_fetched_peer_/2,
    fetch_peers_closest_to_id_/4,
    fetch_peers_closest_to_id_and_not_visited/4,
    peer_already_in_table_/2,
    peers_not_in_table_/2,
    sudo_add_peers_/2,
    update_peer_/3]).

fetch_all_(Table) -> [Peer || [Peer] <- ets:match(Table, '$1')].

fetch_peer_(PeerId, Table) -> ets:lookup(Table, PeerId).

sudo_add_peers_(Peers, Table) -> ets:insert(Table, Peers).

delete_peers_(Peers, Table) ->
    lists:foreach(fun(Peer) -> ets:delete(Table, Peer) end, Peers).

fetch_all_peers_to_ask_for_peers_(Table, MaxTimeSinceLastRequest) ->
    Now = erlang:system_time(milli_seconds),
    MatchSpec = ets:fun2ms(
        fun(#peer{pid=PeerPid, last_peerlist_request=LastRequest} = Peer) when (Now - LastRequest > MaxTimeSinceLastRequest) -> PeerPid end),
    ets:select(Table, MatchSpec).

fetch_all_peers_to_ping_(Table, MaxTimeSinceLastSpoke) ->
    Now = erlang:system_time(milli_seconds),
    MatchSpec = ets:fun2ms(
        fun(#peer{pid=PeerPid, last_spoke=LastSpoke} = Peer) when (Now - LastSpoke > MaxTimeSinceLastSpoke) -> PeerPid end),
    ets:select(Table, MatchSpec).

fetch_last_fetched_peer_(Table, PeerId) ->
    [Peer] = ets:lookup(Table, PeerId),
    Peer#peer.last_fetched_peer.

fetch_peers_closest_to_id_and_not_visited(Table, Id, MaxDist, MaxVals)
    MatchSpec = ets:fun2ms(
        fun(#peer{id=PeerId, address=Address, server_port=Port, process_status=Status} = _Peer) when (PeerId bxor Id < MaxDist), Status =:= done ->
            #peer{id=PeerId, address=Address, server_port=Port} end),
    fetch_peers_closest_to_id_1(Table, Id, MaxVals, MatchSpec).

fetch_peers_closest_to_id_(Table, Id, MaxDist, MaxVals) ->
    MatchSpec = ets:fun2ms(
        fun(#peer{id=PeerId, address=Address, server_port=Port} = _Peer) when (PeerId bxor Id < MaxDist) ->
            #peer{id=PeerId, address=Address, server_port=Port} end),
    fetch_peers_closest_to_id_1(Table, Id, MaxVals, MatchSpec).

fetch_peers_closest_to_id_1(Table, Id, MaxVals, MatchSpec)
    Sorter = fun(Peer1, Peer2) -> Peer1#peer.id bxor Id < Peer2#peer.id bxor Id end,
    FormatList = fun(Peers) -> lists:sublist(lists:sort(Sorter, Peers), MaxVals) end,
    fetch_peers_closest_to_id_2(ets:select(Table, MatchSpec, ?MAX_TABLE_FETCH), [], FormatList).
fetch_peers_closest_to_id_2('$end_of_table', Results, FormatList) -> FormatList(Results);
fetch_peers_closest_to_id_2({NextResult, Continuation}, ResultsSoFar, FormatList) ->
    fetch_peers_closest_to_id_2(ets:select(Continuation), FormatList(NextResult ++ ResultsSoFar)).

peer_already_in_table_(Peer, Table) ->
    case fetch_peer_(Peer#peer.id, Table) of
        [] -> false;
        _ -> true
    end.

update_peer_(PeerId, Updates, Table) ->
    UpdatesMap = maps:from_list(Updates),
    Fields = record_info(fields, peer),
    [Peer] = fetch_peer_(PeerId, Table),
    [peer|Values] = tuple_to_list(Peer),
    UpdatedValues = lists:map(
        fun(Field) -> updating_peer__(Field, UpdatesMap) end,
        lists:zip(Fields, Values)),
    sudo_add_peers_([list_to_tuple([peer | UpdatedValues])], Table).

updating_peer__({FieldName, FieldValue}, Update) ->
    case maps:is_key(FieldName, Update) of
        true -> maps:get(FieldName, Update);
        false -> FieldValue
    end.

fetch_all_servers_(TimeStamp, Table) ->
    MatchSpec = ets:fun2ms(fun(#peer{server_port=Port, time_added=TimeAdded} = Peer) when (Port =/= none), (TimeAdded > TimeStamp) -> Peer end),
    [Peer || Peer <- ets:select(Table, MatchSpec)].

insert_if_not_exists_(PeerId, Table) ->
    case fetch_peer_(PeerId, Table) of
        [] -> 
            sudo_add_peers_([#peer{id=PeerId}], Table),
            peer_inserted;
        _ ->
            peer_exists
    end.


peers_not_in_table_(Peers, Table) ->
    lists:filter(
        fun(#peer{id=Id} = _Peer) ->
            case fetch_peer_(Id, Table) of
                [] -> true;
                _ -> false
            end
        end, Peers).
