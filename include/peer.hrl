-record(node_config, {id, address, bootstrap_peers}).
-record(id, {bin, b64}).
-record(hello, {id, server_port}).
-record(peer, {id, connection_port, address, server_port, peer_pid, time_added, last_spoke, last_fetched_peer, last_peerlist_request=0}).

-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
