package main

import (
	"bufio"
	"net"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Each command and its arguments, with the call the bash scripts made
func TestCallFor(t *testing.T) {
	tests := []struct {
		name      string
		args      []string
		recording bool
		want      string
	}{
		{"app-menu", nil, false, "launcher toggleAppMenu"},
		{"clipboard-menu", nil, false, "clipboard toggleClipboardMenu"},
		{"keybind-menu", nil, false, "keybinds toggleKeybindMenu"},
		{"power-menu", nil, false, "power togglePowerMenu"},

		{"date-panel", nil, false, "datePanel toggleDatePanel"},
		{"date-panel", []string{"--pointer"}, false, "datePanel toggleDatePanelAtPointer"},
		{"date-panel", []string{"--other"}, false, "datePanel toggleDatePanel"},
		{"notification-center", nil, false, "notificationCenter toggleNotificationCenter"},
		{"notification-center", []string{"--pointer"}, false, "notificationCenter toggleNotificationCenterAtPointer"},
		{"toolbox", nil, false, "toolbox toggleToolbox"},
		{"toolbox", []string{"--pointer"}, false, "toolbox toggleToolboxAtPointer"},

		{"record-menu", nil, false, "record toggleRecordMenu"},
		{"record-menu", nil, true, "record toggleLiveMenu"},

		{"scratchpad-menu", nil, false, "scratchpad toggleScratchpadMenu"},
		{"scratchpad-menu", []string{"--tap"}, false, "scratchpad tap"},
		{"scratchpad-menu", []string{"--open"}, false, "scratchpad openScratchpadMenu"},
		{"scratchpad-menu", []string{"--close"}, false, "scratchpad closeScratchpadMenu"},

		{"control-panel", nil, false, "controlPanel toggleControlPanel"},
		{"control-panel", []string{"--pointer"}, false, "controlPanel toggleControlPanelAtPointer"},
		{"control-panel", []string{"Network"}, false, "controlPanel openSection Network"},
		{"control-panel", []string{"--pointer", "Bluetooth"}, false, "controlPanel openSectionAtPointer Bluetooth"},
		{"control-panel", []string{""}, false, "controlPanel toggleControlPanel"},

		{"launcher-call", []string{"pomodoro", "toggle"}, false, "pomodoro toggle"},
		{"launcher-call", []string{"record", "countdown", "123 0,0 10x10"}, false, "record countdown 123 0,0 10x10"},
		{"launcher-call", nil, false, ""},
	}
	for _, test := range tests {
		got := strings.Join(callFor(test.name, test.args, test.recording), " ")
		if got != test.want {
			t.Errorf("%s %q (recording %v) = %q, want %q", test.name, test.args, test.recording, got, test.want)
		}
	}
}

// A stand-in for the daemon: reads one line, then closes, like shell.qml
func fakeDaemon(t *testing.T) (socket string, lines chan string) {
	socket = filepath.Join(t.TempDir(), "test.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	lines = make(chan string, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		line, _ := bufio.NewReader(conn).ReadString('\n')
		conn.Close()
		lines <- line
	}()
	return socket, lines
}

func TestSend(t *testing.T) {
	socket, lines := fakeDaemon(t)
	start := time.Now()
	if err := send(socket, []string{"controlPanel", "openSection", "Network"}); err != nil {
		t.Fatal(err)
	}
	if got := <-lines; got != "controlPanel openSection Network\n" {
		t.Errorf("sent %q", got)
	}
	// The daemon closed straight away, so no waiting out the deadline
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Errorf("took %v", elapsed)
	}
}

func TestSendNoDaemon(t *testing.T) {
	if send(filepath.Join(t.TempDir(), "missing.sock"), []string{"a", "b"}) == nil {
		t.Error("sending to a missing socket should fail")
	}
}

func TestSocketPath(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", "/run/user/1234")
	if got := socketPath(); got != "/run/user/1234/mangifera-launcher.sock" {
		t.Errorf("got %q", got)
	}
	t.Setenv("XDG_RUNTIME_DIR", "")
	if !strings.HasSuffix(socketPath(), "/mangifera-launcher.sock") || !strings.HasPrefix(socketPath(), "/run/user/") {
		t.Errorf("got %q", socketPath())
	}
}

func TestMatchers(t *testing.T) {
	me := os.Getuid()
	daemon := process{uid: me, cmdline: []string{"qs", "-c", "launcher", "-d"}}
	if !isLauncherDaemon(daemon) {
		t.Error("should match the launcher daemon")
	}
	for _, p := range []process{
		{uid: me, cmdline: []string{"qs", "-c", "launcher"}},
		{uid: me, cmdline: []string{"/usr/bin/qs", "-c", "launcher", "-d"}},
		{uid: me + 1, cmdline: []string{"qs", "-c", "launcher", "-d"}},
	} {
		if isLauncherDaemon(p) {
			t.Errorf("shouldn't match %+v (exact command, your own)", p)
		}
	}

	if !isLocker(process{uid: me, cmdline: []string{"qs", "-c", "lock", "-d"}}) {
		t.Error("should match the locker")
	}
	if isLocker(process{uid: me, cmdline: []string{"qs", "-c", "launcher", "-d"}}) {
		t.Error("the launcher isn't the locker")
	}
}

func TestSplitCmdline(t *testing.T) {
	got := splitCmdline([]byte("qs\x00-c\x00launcher\x00-d\x00"))
	if !slices.Equal(got, []string{"qs", "-c", "launcher", "-d"}) {
		t.Errorf("got %q", got)
	}
	if splitCmdline(nil) != nil {
		t.Error("kernel threads have no command line")
	}
}

// findProcess sees real processes: this test's own parent, at least
func TestFindProcess(t *testing.T) {
	parent, ok := readProcess(filepath.Join("/proc", strconv.Itoa(os.Getppid())))
	if !ok || parent.name == "" {
		t.Fatalf("couldn't read the parent process: %+v", parent)
	}
	if !findProcess(func(p process) bool { return p.name == parent.name }) {
		t.Errorf("didn't find %q", parent.name)
	}
	if findProcess(func(p process) bool { return p.name == "no-such-process-name" }) {
		t.Error("found a process that doesn't exist")
	}
}
