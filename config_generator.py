from json import JSONDecoder, JSONEncoder
import socket

def test_json_api():
    decode = JSONDecoder()
    def parse_json(raw_data):
        try:
            py_json, pos = decode.raw_decode(raw_data.encode('utf-8'))
        except ValueError:
            return None, raw_data
        return py_json, raw_data[pos:]

    ADDRESS = "10.0.2.6"
    PORT = 4999

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((ADDRESS, PORT))
    print('wooot')
    s.send(b'{"hej":"dav"}')
    s.close()

class Address:
    config_str = '{{"{ip}", {port}}}'

    def __init__(self, port, ip='127.0.0.1'):
        self.ip = ip
        self.port = port

    @property
    def as_config(self):
        return self.config_str.format(ip=self.ip, port=self.port)
        
class Node:
    config_str = '{{node_config, {myid}, {address}, [{init_peers}]}}'

    def __init__(self, address, myid, init_peers=None):
        if init_peers is None:
            init_peers = []
        self.init_peers = init_peers
        self.myid = myid
        self.address = address

    def __hash__(self):
        return self.myid
 
    @property
    def as_config(self):
        init_peers = ', '.join([address.as_config for address in self.init_peers])
        return self.config_str.format(
            myid=self.myid, address=self.address.as_config,
            init_peers=init_peers)

class NodeConfig:
    config_head = """
%% This config have been generated by test.py
[{{p2phun, [
    {{json_api_config, {json_api}}},
    {{nodes, [
"""

    config_tail = """
        ]}
]}]."""

    def __init__(self, nodes, json_api=None):
        self.nodes = nodes
        self.json_api = json_api

    def __repr__(self):
        nodes = ',\n'.join([node.as_config for node in self.nodes])
        config_head = self.config_head.format(json_api=self.json_api.as_config)
        return config_head + nodes + self.config_tail

if __name__ == '__main__':
    number_of_nodes = 100 
    node_ids = range(2, number_of_nodes + 1)
    nodes= [Node(Address(5000 + n), n, init_peers=[Address(5000 + (n - 1))]) for n in node_ids]
    nodes.append(Node(Address(5001), 1, init_peers=[]))
    nodecfg = NodeConfig(nodes, json_api=Address(4999))
    print(nodecfg)
