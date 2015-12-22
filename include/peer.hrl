-define(MAX_TABLE_FETCH, 100).
-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
-define(ROUTINGTABLE(Id), p2phun_utils:id2proc_name(peer_table, Id)).
-define(KEYSPACE_SIZE, math:pow(2, 6 * 8)). % Present keyspace_size as used in python config generator script-record(node_config, {id, address, bootstrap_peers}).

-record(id, {bin, b64}).
-record(hello, {id, server_port}).
-record(node_config, {id, address, bootstrap_peers}).

-record(peer, {
    id :: p2phun_types:id(),
    connection_port=none :: none | inet:port_number(),
    address :: nonempty_string(),
    server_port,
    pid=none :: none | pid(), % pid of process that maintains the connection with this peer
    time_added :: integer(),
    processed=false :: true | false,
    last_spoke=0 :: integer(),
    last_fetched_peer=0 :: integer(),
    last_peerlist_request=0 :: integer()
    }).
