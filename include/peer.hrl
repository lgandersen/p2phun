-record(node_config, {id, address, bootstrap_peers}).
-record(id, {bin, b64}).
-record(hello, {id, server_port}).
-record(peer, {id, connection_port, address, server_port=none, peer_pid=none, time_added=unspecified}).

-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
