import socket, json, time

QMP = ("127.0.0.1", 4445)

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
print("enter-down:", qmp_cmd(f, {"execute": "input-send-event", "arguments": {"events": [
    {"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": "ret"}}},
]}}))
time.sleep(0.15)
print("enter-up:", qmp_cmd(f, {"execute": "input-send-event", "arguments": {"events": [
    {"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": "ret"}}},
]}}))
s.close()
print("done")
