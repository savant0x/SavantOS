#!/usr/bin/env python3
"""Drive real input into the running dev VM over QMP (clipboard FID repro).

Usage:
  qmp-input.py click X Y       # move the tablet pointer and left-click
  qmp-input.py key ctrl+a      # press combo(s): modifiers held, last key tapped
Keys use QEMU qcodes (ctrl, alt, shift, meta_l, a-z, ret, spc...).
Coordinates are in guest pixels; the abs axis range is scaled from the
guest's 2560x1440 mode (verified against the earlier QMP click script).
"""
import json
import socket
import sys
import time

QMP = ("127.0.0.1", 4445)
ABS = 0x7FFF
W, H = 2560, 1369


def cmd(f, c):
    f.write((json.dumps(c) + "\n").encode())
    f.flush()
    while True:
        line = f.readline().decode().strip()
        if not line:
            return None
        m = json.loads(line)
        if "return" in m or "error" in m:
            return m


def event(f, ev):
    return cmd(f, {"execute": "input-send-event", "arguments": {"events": [ev]}})


def keys(f, *codes):
    evs = [{"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": c}}} for c in codes]
    evs += [{"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": c}}} for c in reversed(codes)]
    return cmd(f, {"execute": "input-send-event", "arguments": {"events": evs}})


def main():
    s = socket.create_connection(QMP, timeout=8)
    f = s.makefile("rwb")
    f.readline()
    cmd(f, {"execute": "qmp_capabilities"})

    action = sys.argv[1]
    if action == "click":
        x, y = int(sys.argv[2]), int(sys.argv[3])
        cmd(f, {"execute": "input-send-event", "arguments": {"events": [
            {"type": "abs", "data": {"axis": "x", "value": int(x / W * ABS)}},
            {"type": "abs", "data": {"axis": "y", "value": int(y / H * ABS)}},
        ]}})
        time.sleep(0.5)
        event(f, {"type": "btn", "data": {"down": True, "button": "left"}})
        time.sleep(0.15)
        event(f, {"type": "btn", "data": {"down": False, "button": "left"}})
    elif action == "key":
        for combo in sys.argv[2:]:
            keys(f, *combo.split("+"))
            time.sleep(0.3)
    else:
        print("unknown action", action, file=sys.stderr)
        sys.exit(2)
    s.close()
    print("ok")


main()
