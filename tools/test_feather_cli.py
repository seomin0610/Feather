#!/usr/bin/env python3
"""Checks app lookup in the CLI, the one bit with branches worth breaking."""

import os
from importlib.machinery import SourceFileLoader

cli = SourceFileLoader("feather_cli", os.path.join(os.path.dirname(__file__), "feather")).load_module()

APPS = [
    {"uuid": "aaaa-1111", "name": "Delta", "version": "1", "signed": False},
    {"uuid": "bbbb-2222", "name": "Delta Lite", "version": "2", "signed": True},
    {"uuid": "cccc-3333", "name": None, "version": None, "signed": False},
]

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

print("ok")
