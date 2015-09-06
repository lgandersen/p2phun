-record(node_config, {id, ip, port, initial_peers}).
-record(peer, {id, port, address}).
-record(peerstate, {my_id, peer_id, we_connected, fsm_pid, sock, transport, address, port, response_table=no_table, response_id=no_id}).

%-define(MAX_PEERID, binary_to_integer(float_to_binary(math:pow(2,128), [{decimals, 0}]))).
-define(MAX_PEERID, binary_to_integer(float_to_binary(1.0e3, [{decimals, 0}]))).

