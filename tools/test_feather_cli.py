#!/usr/bin/env python3
"""Checks the two bits with branches worth breaking: app lookup and pairing."""

import hashlib
import http.server
import json
import os
import socket
import tempfile
import threading
import time
from importlib.machinery import SourceFileLoader

cli = SourceFileLoader("feather_cli", os.path.join(os.path.dirname(__file__), "feather")).load_module()

APPS = [
    {"uuid": "aaaa-1111", "name": "Delta", "version": "1", "signed": False},
    {"uuid": "bbbb-2222", "name": "Delta Lite", "version": "2", "signed": True},
    {"uuid": "cccc-3333", "name": None, "version": None, "signed": False},
]

REAL_CALL = cli.call
cli.call = lambda *args, **kwargs: {"apps": APPS}


def fails(ref):
    try:
        cli.resolve(ref)
    except SystemExit:
        return True
    return False


assert cli.resolve("aaaa-1111") == "aaaa-1111"      # exact uuid wins over the name match
assert cli.resolve("bbbb") == "bbbb-2222"           # uuid prefix
assert cli.resolve("lite") == "bbbb-2222"           # name, case insensitive
assert cli.resolve("cccc-3333") == "cccc-3333"      # nameless app
assert fails("delta")                               # ambiguous
assert fails("nope")                                # no match

# MARK: pairing

cli.call = REAL_CALL
SEEN = {}


class FakeDevice(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        SEEN.update(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        SEEN["auth"] = self.headers.get("Authorization")
        time.sleep(0.2)  # someone tapping Allow and typing the code

        body = json.dumps({"token": "tok-from-device", "device": "iPhone"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeDevice)
threading.Thread(target=server.serve_forever, daemon=True).start()

cli.CONFIG = os.path.join(tempfile.mkdtemp(), "feather-cli.json")


class Args:
    host = "http://127.0.0.1:%d" % server.server_address[1]
    token = None
    usb = False
    udid = None
    name = None
    port = 8420


cli.cmd_login(Args())

stored = json.load(open(cli.CONFIG))
assert stored["devices"]["iPhone"]["token"] == "tok-from-device"   # token comes from the device
assert stored["current"] == "iPhone"                               # and it becomes the default
assert SEEN["auth"] is None                                        # pairing carries no token
assert len(SEEN["codeHash"]) == 64                                 # the code itself never leaves
assert oct(os.stat(cli.CONFIG).st_mode)[-3:] == "600"              # it holds a credential


# MARK: several devices

cli.cmd_login(Args())                                              # same name again
assert sorted(json.load(open(cli.CONFIG))["devices"]) == ["iPhone", "iPhone 2"]

cli.SELECTED = "iPhone"
assert cli.config()[1] == "tok-from-device"                        # --device picks that one

cli.SELECTED = "nope"
try:
    cli.config()
    raise AssertionError("an unknown device must not fall back to another one")
except SystemExit:
    pass
cli.SELECTED = None


# MARK: config written before multi-device

single = os.path.join(tempfile.mkdtemp(), "feather-cli.json")
with open(single, "w") as f:
    json.dump({"host": "http://127.0.0.1:8420", "token": "old"}, f)

cli.CONFIG = single
migrated = cli.load()
assert migrated["current"] == "device" and migrated["devices"]["device"]["token"] == "old"

# MARK: usb tunnel

listener = socket.socket()
listener.bind(("127.0.0.1", 0))
listener.listen(1)
taken = listener.getsockname()[1]

assert cli.port_open(taken)
cli.ensure_tunnel(taken, 8420)  # something already answers, so it must not spawn anything

listener.close()
assert not cli.port_open(taken)

print("ok")
