-module(p2phun_peertable_operations_tests).
-include("peer.hrl").
-include_lib("eunit/include/eunit.hrl").

create_table(Peers2Insert) ->
    MyId = 0,
    Table = ?ROUTINGTABLE(MyId),
    ets:new(Table, [ordered_set, named_table, {keypos, 2}]),
    p2phun_peertable_operations:sudo_add_peers_(Table, Peers2Insert),
    {MyId, Table}.

peers_not_in_table_test() ->
    PeersInTable = [#peer{id=11}, #peer{id=12}],
    {_, Table} = create_table(PeersInTable),
    [#peer{id=13}] = p2phun_peertable_operations:peers_not_in_table_(Table, [#peer{id=13}]),
    [#peer{id=13}] = p2phun_peertable_operations:peers_not_in_table_(Table, [#peer{id=12}, #peer{id=13}]),
    [] = p2phun_peertable_operations:peers_not_in_table_(Table, [#peer{id=11}, #peer{id=12}]),
    ets:delete(Table).

update_peer_test() ->
    PeerId = 1337,
    MockTime = 31337,
    NewServerPort = 2337,
    NewTimeAdded = erlang:system_time(milli_seconds),
    PeersInTable = [#peer{id=PeerId, time_added=MockTime, last_fetched_peer=MockTime}],
    {_, Table} = create_table(PeersInTable),
    p2phun_peertable_operations:update_peer_(Table, PeerId, [{time_added, NewTimeAdded}, {server_port, NewServerPort}]),
    [Peer] = p2phun_peertable_operations:fetch_peer_(Table, PeerId),
    MockTime = Peer#peer.last_fetched_peer,
    0 = Peer#peer.last_peerlist_request,
    NewServerPort = Peer#peer.server_port,
    NewTimeAdded = Peer#peer.time_added,
    ets:delete(Table).

% This test could be expanded
fetch_peer_closest_to_id_test() ->
    PeersInTable = [
        #peer{id=2}, #peer{id=4}, #peer{id=8},
        #peer{id=16}, #peer{id=32}, #peer{id=64}],
    {MyId, Table} = create_table(PeersInTable),
    ExpectedResult = sets:from_list([#peer{id=2}, #peer{id=4}, #peer{id=8}]),
    Result = sets:from_list(p2phun_peertable_operations:fetch_peers_closest_to_id_(Table, MyId, 1, 10)),
    true = sets:is_subset(Result, ExpectedResult),
    true = sets:is_subset(ExpectedResult, Result),
    ets:delete(Table).
