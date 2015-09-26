-record(node_config, {id, address, bootstrap_peers}).
-record(hello, {id, server_port}).
-record(peer, {id, connection_port, address, server_port=none, peer_pid=none}).
-record(peerstate, {my_id, peer_id, we_connected, peer_pid, sock, transport, address, port, callers_pid=no_receiver}).

-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
