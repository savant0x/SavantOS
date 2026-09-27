import socket, json, time

QMP = ("127.0.0.1", 4445)
ABS = 0x7FFF
W, H = 2560, 1440

def qmp_cmd(f, cmd):
    f.write((json.dumps(cmd) + "\n").encode())
    f.flush()
    while True:
        line = f.readline().decode().strip()
        if not line:
            return None
        msg = json.loads(line)
        if "return" in msg or "error" in msg:
            return msg

s = socket.create_connection(QMP, timeout=8)
f = s.makefile("rwb")
f.readline()
qmp_cmd(f, {"execute": "qmp_capabilities"})

x, y = 1373, 789  # OK button in guest coords
print("move:", qmp_cmd(f, {"execute": "input-send-event", "arguments": {"events": [
    {"type": "abs", "data": {"axis": "x", "value": int(x / W * ABS)}},
    {"type": "abs", "data": {"axis": "y", "value": int(y / H * ABS)}},
]}}))
time.sleep(0.6)
print("down:", qmp_cmd(f, {"execute": "input-send-event", "arguments": {"events": [
    {"type": "btn", "data": {"down": True, "button": "left"}},
]}}))
time.sleep(0.2)
print("up:", qmp_cmd(f, {"execute": "input-send-event", "arguments": {"events": [
    {"type": "btn", "data": {"down": False, "button": "left"}},
]}}))
s.close()
print("done")
