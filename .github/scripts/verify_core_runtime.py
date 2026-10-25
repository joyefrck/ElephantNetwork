import argparse
import http.server
import json
import pathlib
import socket
import struct
import subprocess
import tempfile
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("core", type=pathlib.Path)
parser.add_argument("receipt", type=pathlib.Path)
args = parser.parse_args()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == '/slow':
            time.sleep(0.4)
        self.send_response(204)
        self.send_header('Content-Length', '0')
        self.end_headers()
    def log_message(self, *args):
        pass

checks = {}
with tempfile.TemporaryDirectory(prefix='elephant-core-accept-') as temp:
    home = pathlib.Path(temp)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(home / 'ipc'))
    server.listen(1)
    server.settimeout(15)
    http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    http.daemon_threads = True
    threading.Thread(target=http.serve_forever, daemon=True).start()
    with (home / 'runtime.log').open('w') as log:
        proc = subprocess.Popen([str(args.core.resolve()), str(home / 'ipc')], stdout=log, stderr=log)
        try:
            connection, _ = server.accept()
            connection.settimeout(15)
            counter = 0
            def read_exact(size):
                result = b''
                while len(result) < size:
                    part = connection.recv(size - len(result))
                    if not part:
                        raise RuntimeError('Core disconnected')
                    result += part
                return result
            def call(method, arguments=None):
                global counter
                counter += 1
                ident = str(counter)
                payload = json.dumps({'id': ident, 'method': method, 'arguments': arguments}).encode()
                connection.sendall(struct.pack('<I', len(payload)) + payload)
                while True:
                    size = struct.unpack('<I', read_exact(4))[0]
                    answer = json.loads(read_exact(size))
                    if answer.get('id') != ident:
                        continue
                    assert not answer.get('error'), answer
                    if answer.get('file'):
                        path = pathlib.Path(answer['file'])
                        assert path.parent == home / 'responses', path
                        stored = path.stat().st_size
                        answer = json.loads(path.read_text())
                        path.unlink()
                        assert answer['id'] == ident
                        checks['large_response'] = {'frame_bytes': size, 'file_bytes': stored}
                    return answer.get('result')
            assert call('initClash', {'home-dir': str(home), 'version': 20007}) is True
            config = {
                'mixed-port': 0,
                'mode': 'rule',
                'dns': {'enable': True, 'listen': '', 'enhanced-mode': 'fake-ip', 'fake-ip-filter': [], 'nameserver': ['https://1.1.1.1/dns-query']},
                'proxy-groups': [{'name': 'Exit', 'type': 'select', 'proxies': ['DIRECT']}],
                'rules': ['MATCH,Exit'],
            }
            (home / 'config.yaml').write_text(json.dumps(config))
            setup = call('setupConfig', {'selected-map': {'Exit': 'DIRECT'}, 'test-url': 'https://example.com'})
            assert setup == '', setup
            before = call('getProxies')
            patch = {'dns': {**config['dns'], 'cache-max-size': 8192}, 'hosts': {'test.invalid': '127.0.0.2'}, 'ntp': {'enable': False}, 'sniffer': {'enable': False}}
            assert call('updateRuntimeConfig', patch) == ''
            after = call('getProxies')
            if before != after:
                (home / 'proxies-before.json').write_text(json.dumps(before, indent=2))
                (home / 'proxies-after.json').write_text(json.dumps(after, indent=2))
            assert before == after
            checks['runtime_update_preserves_groups'] = True
            failure = call('updateRuntimeConfig', {'dns': {'enable': True, 'nameserver': ['unsupported://resolver']}})
            assert failure, failure
            assert call('getProxies') == before
            checks['invalid_runtime_update_preserves_groups'] = True
            assert call('clearDnsCache') is True
            assert call('resetNetwork') is True
            checks['network_and_cache_methods'] = True
            fast = call('asyncTestDelay', {'proxy-name': 'DIRECT', 'timeout': 3000, 'test-url': f'http://127.0.0.1:{http.server_port}/fast'})
            assert fast['value'] >= 1, fast
            slow = call('asyncTestDelay', {'proxy-name': 'DIRECT', 'timeout': 100, 'test-url': f'http://127.0.0.1:{http.server_port}/slow'})
            assert slow['value'] == -1, slow
            checks['delay_timeout_and_submillisecond_result'] = True
            config['proxies'] = [{'name': f'node-{i}', 'type': 'socks5', 'server': '127.0.0.1', 'port': 1080} for i in range(20000)]
            profile = home / 'large.yaml'
            profile.write_text(json.dumps(config))
            result = call('getConfig', str(profile))
            assert len(result['proxies']) == 20000
            assert checks['large_response']['file_bytes'] > 1024 * 1024
            assert not list((home / 'responses').glob('*.json'))
            checks['large_response_count'] = 20000
            assert call('shutdown') is True
            connection.close()
            proc.wait(timeout=10)
            assert proc.returncode == 0, proc.returncode
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
            http.shutdown()
            server.close()
args.receipt.write_text(json.dumps(checks, indent=2))
print(json.dumps(checks, indent=2))
