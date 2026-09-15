package main

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"time"
)

// notifySocket implements the datagram write side of sd_notify(3): send
// "READY=1" to the socket named by $NOTIFY_SOCKET. Abstract-namespace
// addresses (the "@..." form systemd uses for user units) are stripped of
// the marker and dialed with the leading-NUL encoding. Best-effort by
// contract: an error is reported, never fatal (systemd's start-up timeout
// is the backstop; a failed notify must not take the daemon down).
func notifySocket(sock string) error {
	return notifySend(sock, "READY=1")
}

func notifySend(sock, state string) error {
	c, err := net.Dial("unixgram", notifyAddr(sock))
	if err != nil {
		return fmt.Errorf("sd_notify dial %q: %w", sock, err)
	}
	defer c.Close()
	if _, err := c.Write([]byte(state)); err != nil {
		return fmt.Errorf("sd_notify write: %w", err)
	}
	return nil
}

// watchdogLoop services the unit's WatchdogSec contract: systemd expects a
// "WATCHDOG=1" datagram every interval/2 once Type=notify + WatchdogSec are
// set, and kills the service otherwise. A hung core therefore gets killed
// and restarted WITHOUT capability — exactly the fail-closed property the
// safety law wants (FID-2026-0915-004). Sends stop if the socket ever
// refuses, which lets systemd do its job.
func watchdogLoop() {
	sock := os.Getenv("NOTIFY_SOCKET")
	usecStr := os.Getenv("WATCHDOG_USEC")
	if sock == "" || usecStr == "" {
		return // no watchdog supervision in this environment
	}
	usec, err := strconv.ParseInt(usecStr, 10, 64)
	if err != nil || usec <= 0 {
		return
	}
	interval := time.Duration(usec/2) * time.Microsecond
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for range t.C {
			if notifySend(sock, "WATCHDOG=1") != nil {
				return
			}
		}
	}()
}
