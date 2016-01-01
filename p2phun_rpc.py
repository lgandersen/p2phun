import pickle
import time
from json import JSONDecoder, JSONEncoder
import socket

from config_generator import Node, Address

with open('nodes.pickle', 'rb') as f:
    nodes = pickle.load(f)
decode = JSONDecoder()

def _parse_json(raw_data):
    try:
        py_json, pos = decode.raw_decode(raw_data.decode('utf-8'))
    except ValueError:
        return None, raw_data
    return py_json, raw_data[pos:]

class P2PhunRPC:
    def __init__(self, address, port):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect((address, port))
        self.s = s
        self.buf = b''

    def _get_result(self):
        while True:
            self.buf += self.s.recv(1024)
            time.sleep(1)
            py_json, data_rest = _parse_json(self.buf)
            if py_json is not None:
                self.buf = data_rest
                return py_json
    
    def fetch_routing_table(self, my_id):
        self.s.send(b'{"mod":"p2phun_peertable_operations", "fun":"fetch_all", "args":"' + my_id + b'"}')
        return self._get_result()

    def find_node(self, my_id, id2find):
        msg = b'{"mod":"p2phun_swarm", "fun":"find_node", "args":["' + my_id + b'","' + id2find + b'"]}'
        self.s.send(msg)
    
    def shutdown(self):
        self.s.close()

if __name__ == '__main__':
    ADDRESS = "10.0.2.6"
    PORT = 4999
    rpc = P2PhunRPC(ADDRESS, PORT)
    swarm_ids = [node.myid_b64 for node in nodes]
    #result = [rpc.fetch_routing_table(peer_id) for peer_id in swarm_ids]
    #print(result)
    node_id = nodes[0].myid_b64
    id2find = nodes[1].myid_b64
    rpc.find_node(node_id, id2find)
