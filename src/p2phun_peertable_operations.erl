-module(p2phun_peertable_operations).
-include("peer.hrl").

%-import(p2phun_peertable_operations, [
%    peers_not_in_table_/2, insert_if_not_exists_/2,
%    fetch_all_servers_/2, update_peer_/3,
%    peer_already_in_table_/2, fetch_peers_closest_to_id_/3,
%    fetch_last_fetched_peer_/2, fetch_all_peers_to_ping_/2,
%    fetch_all_peers_to_ask_for_peers_/2, fetch_peer_/2,
%    fetch_all_/1, sudo_add_peers_/2, delete_peers_/2]).

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

fetch_peers_closest_to_id_(Table, Id, Neighbourhood) ->
    MatchSpec = ets:fun2ms(
        fun(#peer{id=PeerId, address=Address, server_port=Port} = _Peer) when (PeerId bxor Id < Neighbourhood) ->
            #peer{id=PeerId, address=Address, server_port=Port} end),
    fetch_peers_closest_to_id_1(ets:select(Table, MatchSpec, 200), []).
fetch_peers_closest_to_id_1('$end_of_table', ResultsSoFar) -> ResultsSoFar;
fetch_peers_closest_to_id_1({NextResult, Continuation}, ResultsSoFar) ->
    % We should do some removing of worst results here
    fetch_peers_closest_to_id_1(ets:select(Continuation), NextResult ++ ResultsSoFar).

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
