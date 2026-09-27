#!/bin/bash
# Run a GUI probe inside the SavantOS Plasma session with the manager's env.
# Usage: probe-gui.sh '<command...>'  (executed via systemd-run --user)
exec ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 savant@127.0.0.1 \
  "systemd-run --user env XDG_RUNTIME_DIR=/run/user/1000 $1"
