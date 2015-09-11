-record(node_config, {id, ip, port, initial_peers}).
-record(peer, {id, port, address, listening_port=none, peer_pid=none}).
-record(peerstate, {my_id, peer_id, we_connected, peer_pid, sock, transport, address, port, callers_pid=no_receiver}).

%-define(MAX_PEERID, binary_to_integer(float_to_binary(math:pow(2,128), [{decimals, 0}]))).
-define(MAX_PEERID, binary_to_integer(float_to_binary(1.0e3, [{decimals, 0}]))).

