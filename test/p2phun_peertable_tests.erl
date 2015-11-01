-module(p2phun_peertable_tests).

-include_lib("eunit/include/eunit.hrl").

-include("peer.hrl").
-record(state, {tablename, id, space_size, bigbin, bigbin_size, smallbins, smallbin_size}).

create_interval_sequence_test() ->
    [1,4,7,10] = p2phun_peertable:create_interval_sequence(1, 10, 3),
    [1,2,3,4,5,6,7,8,9,10] = p2phun_peertable:create_interval_sequence(1, 10, 5),
    [1,4,6,8,10,12,14,16,18,20] = p2phun_peertable:create_interval_sequence(1, 20, 8),
    [1,21,41,61,81,100] = p2phun_peertable:create_interval_sequence(1, 100, 5).

create_intervals_test() ->
    [{1,4}, {4,7}, {7,10}] = p2phun_peertable:create_intervals(1, 10, 3),
    [{20, 30}, {30, 40}, {40, 50}] = p2phun_peertable:create_intervals(20, 50, 3).

mockstate(Peers2Insert) ->
    Tablename = testtable,
    ets:new(Tablename, [ordered_set, named_table, {keypos, 2}]),
    SmallBins = p2phun_peertable:create_intervals(20, 50, 3), % Like last line in create_intervals_test/0
    MockState = #state{id=0, bigbin={-1, 20}, smallbins=SmallBins, tablename=Tablename, bigbin_size=3, smallbin_size=2},
    p2phun_peertable:sudo_add_peers_(Peers2Insert, MockState),
    MockState.

bin_of_peer_test() ->
    MockState = mockstate([]),
    BigBin = p2phun_peertable:bin_of_peer(0, MockState),
    BigBin = p2phun_peertable:bin_of_peer(19, MockState),
    BigBin = p2phun_peertable:bin_of_peer(20, MockState),
    {20, 30} = p2phun_peertable:bin_of_peer(30, MockState),
    {30, 40} = p2phun_peertable:bin_of_peer(35, MockState),
    {30, 40} = p2phun_peertable:bin_of_peer(40, MockState),
    ets:delete(MockState#state.tablename).

peers_in_bin_test() ->
    MockState = mockstate([#peer{id=10}, #peer{id=12}, #peer{id=25}]),
    % Try out some corner-cases perhaps?
    [#peer{id=12}, #peer{id=10}] = p2phun_peertable:peers_in_bin({-1, 20}, MockState),
    [#peer{id=25}] = p2phun_peertable:peers_in_bin({20, 30}, MockState),
    [] = p2phun_peertable:peers_in_bin({40, 50}, MockState),
    ets:delete(MockState#state.tablename).

peers_not_in_table_test() ->
    PeersInTable = [#peer{id=11}, #peer{id=12}],
    MockState = mockstate(PeersInTable),
    [#peer{id=13}] = p2phun_peertable:peers_not_in_table_([#peer{id=13}], MockState),
    [#peer{id=13}] = p2phun_peertable:peers_not_in_table_([#peer{id=12}, #peer{id=13}], MockState),
    [] = p2phun_peertable:peers_not_in_table_([#peer{id=11}, #peer{id=12}], MockState),
    ets:delete(MockState#state.tablename).

room_for_peer_test() ->
    PeersInTable = [
        #peer{id=11}, #peer{id=12}, #peer{id=13},
        #peer{id=22}, #peer{id=23}],
    MockState = mockstate(PeersInTable),
    bin_full = p2phun_peertable:room_for_peer(#peer{id=14}, MockState),
    bin_full = p2phun_peertable:room_for_peer(#peer{id=24}, MockState),
    yes = p2phun_peertable:room_for_peer(#peer{id=44}, MockState),
    ets:delete(MockState#state.tablename).

update_peer_test() ->
    PeerId = 1337,
    MockTime = 31337,
    NewServerPort = 2337,
    NewTimeAdded = erlang:system_time(milli_seconds),
    PeersInTable = [#peer{id=PeerId, time_added=MockTime, last_fetched_peer=MockTime}],
    MockState = mockstate(PeersInTable),
    p2phun_peertable:update_peer_(PeerId, [{time_added, NewTimeAdded}, {server_port, NewServerPort}], MockState),
    [Peer] = p2phun_peertable:fetch_peer_(PeerId, MockState),
    MockTime = Peer#peer.last_fetched_peer,
    0 = Peer#peer.last_peerlist_request,
    NewServerPort = Peer#peer.server_port,
    NewTimeAdded = Peer#peer.time_added,
    ets:delete(MockState#state.tablename).
