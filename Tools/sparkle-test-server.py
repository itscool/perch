#!/usr/bin/env python3
"""Loopback-only Sparkle download fault fixture. Never serves a public feed."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import time

parser = argparse.ArgumentParser()
parser.add_argument('--root', required=True, type=Path)
parser.add_argument('--port', required=True, type=int)
parser.add_argument('--control', required=True, type=Path,
                    help='Text file: normal, disconnect or slow; defaults to normal')
args = parser.parse_args()

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        try:
            mode = args.control.read_text().strip()
        except FileNotFoundError:
            mode = 'normal'
        if mode not in ('normal', 'disconnect', 'slow'):
            self.send_error(500, 'Invalid fixture mode'); return
        if not self.path.split('?', 1)[0].endswith('.zip') or mode == 'normal':
            return super().do_GET()
        stream = self.send_head()
        if stream is None:
            return
        sent = 0
        try:
            with stream:
                while chunk := stream.read(65536):
                    self.wfile.write(chunk); self.wfile.flush(); sent += len(chunk)
                    if mode == 'disconnect' and sent >= 131072:
                        self.connection.shutdown(socket.SHUT_RDWR)
                        self.close_connection = True
                        break
                    if mode == 'slow':
                        time.sleep(0.25)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        print(json.dumps({'mode': mode, 'bytesSent': sent, 'path': self.path}), flush=True)

server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=str(args.root.resolve())))
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
