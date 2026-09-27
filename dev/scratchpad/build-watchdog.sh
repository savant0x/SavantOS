#!/bin/bash
# Build-respawn watchdog: launches the dual-build detached and relaunches it
# if the Docker/WSL engine really dies mid-run.
#
# 2026-09-22 correction (FID-2026-0922-001 build evidence): the first version
# probed the engine with `timeout 25 docker info` and treated ONE failure as
# death, then taskkilled Docker Desktop and restarted the build. That
# false-positived during the 6 GB tar->mke2fs leg (the Docker API stalls for
# tens of seconds under that IO), killing a healthy 60-minute assembly.
# Death is now declared only after THREE consecutive failed probes spanning
# ~2 minutes, and the engine is never killed on the first miss.
set -u
cd "$(dirname "$0")/../../guest-image" || exit 1
LOG="$PWD/out/build-$(date +%Y-%m-%d).log"
DOCKER_EXE="/c/Program Files/Docker/Docker/Docker Desktop.exe"
PROBE_TIMEOUT=45   # a loaded engine can take this long to answer
STRIKES_NEEDED=3   # consecutive failures before declaring death
STRIKE_GAP=30      # seconds between strikes (~2 min of sustained failure)

engine_up() { timeout "$PROBE_TIMEOUT" docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; }

wait_engine() { # wait up to 4 min for the engine
  for _ in $(seq 1 24); do engine_up && return 0; sleep 10; done
  return 1
}

start_engine() {
  engine_up && return 0
  powershell -NoProfile -Command "Start-Process '$DOCKER_EXE'" 2>/dev/null
  wait_engine
}

# True only when the engine has failed STRIKES_NEEDED probes in a row.
engine_dead() {
  strike=0
  while [ "$strike" -lt "$STRIKES_NEEDED" ]; do
    if engine_up; then
      return 1
    fi
    strike=$((strike + 1))
    [ "$strike" -lt "$STRIKES_NEEDED" ] && sleep "$STRIKE_GAP"
  done
  return 0
}

attempt=0
while [ "$attempt" -lt 3 ]; do
  attempt=$((attempt + 1))
  echo "[watchdog] attempt $attempt $(date +%H:%M:%S)" >> "$LOG.wd"
  start_engine || { echo "[watchdog] engine unreachable, retrying" >> "$LOG.wd"; sleep 60; continue; }

  bash build.sh > "$LOG" 2>&1 &
  build_pid=$!

  # Monitor: resume only when death is confirmed by sustained failure.
  while kill -0 "$build_pid" 2>/dev/null; do
    sleep 60
    grep -aqE "GATE GREEN|GATE RED|BUILD EXIT" "$LOG" && break
    if engine_dead; then
      echo "[watchdog] engine confirmed dead ($STRIKES_NEEDED strikes), respawning" >> "$LOG.wd"
      kill "$build_pid" 2>/dev/null; sleep 3
      taskkill //IM "Docker Desktop.exe" //F >/dev/null 2>&1
      taskkill //IM "com.docker.backend.exe" //F >/dev/null 2>&1
      sleep 8
      break   # outer loop restarts the build
    fi
  done
  wait "$build_pid" 2>/dev/null
  grep -aqE "GATE GREEN|GATE RED" "$LOG" && { echo "[watchdog] verdict reached, done" >> "$LOG.wd"; exit 0; }
  sleep 20
done
echo "[watchdog] giving up after $attempt attempts" >> "$LOG.wd"
