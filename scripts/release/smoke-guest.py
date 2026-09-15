#!/usr/bin/env python3
"""Boot the factory image and prove the Plasma desktop payload boots."""

from __future__ import annotations

import argparse
import json
import os
import re
import selectors
import subprocess
import sys
import time
from pathlib import Path


SUCCESS = b"SAVANTOS_SMOKE:savant:phase2"
# Facts the factory image must satisfy, checked from inside the booted guest
# and reported on the serial console as SAVANTOS_FACT:<name>:<value>. The
# instant-trial premise is dead on the first-party builder (no
# savantos.instant consumption — grep-verified 2026-09-14); the smoke proves
# the Plasma payload instead (FID-2026-0914-002 step 2).
FACT_CHECKS = {
    "kwin": "test -x /usr/bin/kwin_wayland && echo present || echo missing",
    "plasmashell": "test -x /usr/bin/plasmashell && echo present || echo missing",
    "sddm": "test -x /usr/bin/sddm && echo present || echo missing",
    "colorscheme": "test -f /usr/share/color-schemes/Savant.colors && echo present || echo missing",
    "decoration": "test -f /usr/share/kwin/decorations/savant-traffic-lights/contents/ui/main.qml && echo present || echo missing",
    "kvantum": "test -f /usr/share/Kvantum/Savant/Savant.kvconfig && echo present || echo missing",
    "autologin": "test -f /etc/sddm.conf.d/10-savantos-autologin.conf && echo present || echo missing",
    "display-manager-alias": "test -L /etc/systemd/system/display-manager.service && echo yes || echo no",
    "keyring-unit": "systemctl is-enabled savantos-keyring-init.service 2>/dev/null || true",
    "sddm-enabled": "systemctl is-enabled sddm.service 2>/dev/null || true",
    "sshd": "systemctl is-active sshd 2>/dev/null || true",
    "foreign": "pacman -Qmq 2>/dev/null | wc -l",
    "kernel-modules": "test -f /usr/lib/modules/$(uname -r)/modules.dep.bin && echo yes || echo no",
    "ready-service": "systemctl is-enabled savantos-ready.service 2>/dev/null || true",
}
EXPECTED_FACTS = {
    "kwin": "present",
    "plasmashell": "present",
    "sddm": "present",
    "colorscheme": "present",
    "decoration": "present",
    "kvantum": "present",
    "autologin": "present",
    "display-manager-alias": "yes",
    "keyring-unit": "enabled",
    "sddm-enabled": "enabled",
    "sshd": "inactive",
    "foreign": "0",
    "kernel-modules": "yes",
    "ready-service": "enabled",
}


def parse_facts(transcript: bytes) -> dict[str, str]:
    """Return the last real value printed for each smoke fact.

    The serial console echoes the command before its output and may attach
    terminal escape sequences to the first result, so matches can occur
    anywhere. Echoed printf placeholders are not results.
    """
    facts = {}
    for name, value in re.findall(
        r"SAVANTOS_FACT:([A-Za-z0-9-]+):([^\s\x1b'\"\\]+)(?=\s|\x1b|$)",
        transcript.decode("utf-8", errors="replace"),
    ):
        if "%" not in value:
            facts[name] = value
    return facts


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifacts", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    if not Path("/dev/kvm").exists() or not os.access("/dev/kvm", os.R_OK | os.W_OK):
        raise SystemExit("release smoke test requires accessible /dev/kvm")

    spec = json.loads((args.artifacts / "build-spec.json").read_text(encoding="utf-8"))
    cmdline = spec["runtime"]["kernelCommandLine"]
    cmdline = cmdline.replace("console=tty0 ", "").replace("console=hvc0", "console=ttyS0")
    cmdline += " systemd.unit=multi-user.target"

    command = [
        "qemu-system-x86_64",
        "-nodefaults",
        "-no-reboot",
        "-snapshot",
        "-accel",
        "kvm",
        "-machine",
        "q35",
        "-cpu",
        "host",
        "-smp",
        "4",
        "-m",
        "4096",
        "-display",
        "none",
        "-monitor",
        "none",
        "-serial",
        "stdio",
        "-drive",
        f"file={args.artifacts / 'rootfs.ext4'},format=raw,if=virtio",
        "-kernel",
        str(args.artifacts / "vmlinuz-linux"),
        "-initrd",
        str(args.artifacts / "initramfs-linux.img"),
        "-append",
        cmdline,
        "-device",
        "virtio-rng-pci",
        "-netdev",
        "user,id=net0",
        "-device",
        "virtio-net-pci,netdev=net0",
    ]

    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    assert process.stdin is not None and process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + args.timeout
    transcript = bytearray()
    login_attempts = 0
    sent_command = False
    password_sent_at: float | None = None
    password_offset = 0
    last_login_prompt = -1
    last_password_prompt = -1

    try:
        while time.monotonic() < deadline:
            if process.poll() is not None:
                break
            events = selector.select(timeout=1)
            for key, _ in events:
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    continue
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
                transcript.extend(data)
                if len(transcript) > 1_000_000:
                    del transcript[:-500_000]

                if SUCCESS in transcript:
                    process.wait(timeout=90)
                    facts = parse_facts(bytes(transcript))
                    wrong = {name: (facts.get(name), want) for name, want in EXPECTED_FACTS.items() if facts.get(name) != want}
                    if wrong:
                        raise SystemExit(f"factory guest booted but the image facts are wrong: {wrong}")
                    print("ok - factory guest reached a usable account")
                    print("ok - image facts: " + ", ".join(f"{k}={facts[k]}" for k in sorted(facts)))
                    return

                login_prompt = transcript.rfind(b"login:")
                if login_prompt > last_login_prompt and login_attempts < 20:
                    process.stdin.write(b"savant\n")
                    process.stdin.flush()
                    login_attempts += 1
                    last_login_prompt = login_prompt

                password_prompt = transcript.rfind(b"Password:")
                if password_prompt > last_password_prompt:
                    process.stdin.write(b"savant\n")
                    process.stdin.flush()
                    password_sent_at = time.monotonic()
                    password_offset = len(transcript)
                    last_password_prompt = password_prompt

                if password_sent_at is not None and b"Login incorrect" in transcript[password_offset:]:
                    password_sent_at = None

            if (
                password_sent_at is not None
                and not sent_command
                and time.monotonic() - password_sent_at >= 3
            ):
                checks = "; ".join(
                    f"printf 'SAVANTOS_FACT:{name}:%s\\n' \"$({command})\"" for name, command in FACT_CHECKS.items()
                )
                process.stdin.write(
                    (checks + "; ").encode()
                    + b"printf 'SAVANTOS_SMOKE:%s:%s\\n' \"$(id -un)\" "
                    b"\"$(cat /usr/share/savantos/image-stream 2>/dev/null)\"; "
                    b"sudo systemctl poweroff\n"
                )
                process.stdin.flush()
                sent_command = True
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    tail = bytes(transcript[-8000:]).decode("utf-8", errors="replace")
    raise SystemExit(f"factory guest smoke test failed\n\n{tail}")


if __name__ == "__main__":
    main()
