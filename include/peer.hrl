-define(MAX_TABLE_FETCH, 100).
-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
-define(ROUTINGTABLE(Id), p2phun_utils:id2proc_name(peer_table, Id)).
-define(PEERPOOL(Id), {peer_pool, Id}).
-define(SWARM(Id), {swarm, Id}).
-define(KEYSPACE_SIZE, math:pow(2, 6 * 8)). % Present keyspace_size as used in python config generator script-record(node_config, {id, address, bootstrap_peers}).

-type error() :: {already_started, pid()} | term().
-type id() :: non_neg_integer().
-type table() :: ets:tid() | atom().
-type location() :: {nonempty_string(), inet:port_number()}. %should be inet:address()

-type msg_type() :: got_hello | closing_connection| ping | peer_list | find_node.
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
    address :: inet:ip_address() | inet:hostname(),
    server_port=none,
    pid=none :: none | pid(), % pid of process that maintains the connection with this peer
    time_added=0 :: integer(),
    processed=false :: true | false,
    last_spoke=0 :: integer(),
    last_fetched_peer=0 :: integer(),
    last_peerlist_request=0 :: integer()
    }).

-type peer() :: #peer{}.

-record(search_findings, {
    searcher :: pid(),
    type :: nodes_closer | node_found | no_more_peers_in_cache,
    data=no_data :: no_data | [#peer{}] | {p2phun_types:id(), pid()}
    }).


-record(swarm_state, {my_id, cache, id2find, searchers, nsearchers, idle_searchers, caller_pid}).

-record(peer_state, {
          my_id :: id(),
          peer_id :: id(),
          we_connected :: true | false,
          address :: inet:ip_address() | inet:hostname(),
          port :: inet:port_number(),
          transport :: gen_tcp | ssl,
          sock :: inet:socket(),
          callers=[] :: [pid()]}).


% Test-related:
-define(NODE(Id), #node_config{id=Id, address={?LOCALHOST, 5000 + Id}}).
-define(LOCALHOST, {10,0,2,6}).
-define(PEER(Id), #peer{id=Id, address=?LOCALHOST, server_port=5000 + Id}).
