package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// notifyAddr returns the dial address for a $NOTIFY_SOCKET value: the
// abstract-namespace "@..." form maps to the NUL-prefixed address; concrete
// paths pass through. (Helper extracted so the mapping is unit-testable.)
func notifyAddr(sock string) string {
	if len(sock) > 1 && sock[0] == '@' {
		return "\x00" + sock[1:]
	}
	return sock
}

// checkSocketMode asserts the control socket exists with 0600 permissions —
// the socket IS the security boundary (FID-2026-0915-004), so the mode is
// part of the contract, verified here and at runtime.
func checkSocketMode(sock string) error {
	fi, err := os.Lstat(sock)
	if err != nil {
		return err
	}
	if fi.Mode()&os.ModeSocket == 0 {
		return fmt.Errorf("%s is not a socket", sock)
	}
	if fi.Mode().Perm() != 0o600 {
		return fmt.Errorf("%s mode %o, want 0600", sock, fi.Mode().Perm())
	}
	return nil
}

// mkdirAndWrite creates parent dirs and writes a regular file — used by the
// stale-file test to prove the server never clobbers a stranger's file.
func mkdirAndWrite(path, content string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), 0o600)
}

// dialControl/roundTrip are the client half of the v1 line protocol —
// the same bytes savantctl will speak in m3. Kept here so the wire format
// has exactly one definition beside its server.
func dialControl(sock string) (net.Conn, error) {
	c, err := net.Dial("unix", sock)
	if err != nil {
		return nil, err
	}
	_ = c.SetDeadline(time.Now().Add(10 * time.Second))
	return c, nil
}

func roundTrip(c net.Conn, cmd string) (string, error) {
	if _, err := io.WriteString(c, cmd); err != nil {
		return "", err
	}
	line, err := bufio.NewReader(c).ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimRight(line, "\n"), nil
}
