-define(MAX_TABLE_FETCH, 100).
-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
-define(ROUTINGTABLE(Id), p2phun_utils:id2proc_name(peer_table, Id)).
-define(PEERPOOL(Id), {peer_pool, Id}).
-define(KEYSPACE_SIZE, math:pow(2, 6 * 8)). % Present keyspace_size as used in python config generator script-record(node_config, {id, address, bootstrap_peers}).

-type error() :: {already_started, pid()} | term().
-type id() :: non_neg_integer().
-type table() :: ets:tid() | atom().
-type location() :: {nonempty_string(), inet:port_number()}. %should be inet:address()

-type msg_type() :: hello | closing_connection| ping | peer_list | find_node.
-type msg_kind() :: request | response | connection_control.

-record(msg, {
    kind :: msg_kind(),
    type :: msg_type(),
    data=none :: term()
    }).

-record(hello, {
    id :: id(),
    server_port :: inet:port_number()
    }).

-record(node_config, {
    id :: id() | base64:ascii_string(),
    address :: location(),
    bootstrap_peers=[] :: [location()]
    }).

-record(peer, {
    id :: p2phun_types:id(),
    connection_port=none :: none | inet:port_number(),
    address :: nonempty_string(),
    server_port,
    pid=none :: none | pid(), % pid of process that maintains the connection with this peer
    time_added=0 :: integer(),
    processed=false :: true | false,
    last_spoke=0 :: integer(),
    last_fetched_peer=0 :: integer(),
    last_peerlist_request=0 :: integer()
    }).

-type peer() :: #peer{}.
