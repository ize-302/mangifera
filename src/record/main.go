// record-toggle, record-status and cam-toggle: screen recording.
//
// One binary, three names: install.sh builds it into
// ~/.local/bin/record-toggle, and record-status and cam-toggle are symlinks
// to it. It looks at the name it was run as to know what to do.
//
//	record-toggle [--none|--desktop|--mic|--both] [--camera] [--fps=N]
//	record-toggle --live-sound=<none|desktop|mic|both>
//	record-status
//	cam-toggle [rotate|zoom-in|zoom-out|zoom-reset]
//
// record-toggle starts or stops a recording (see toggle.go); the record menu
// (RecordMenu.qml), the toolbox and the bar run it. record-status is the
// bar's recording indicator, which waybar keeps running (see status.go).
// cam-toggle shows, hides, rotates and zooms the webcam bubble (see
// camera.go).
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

func main() {
	name := filepath.Base(os.Args[0])
	var err error
	switch name {
	case "record-status":
		err = recordStatus()
	case "cam-toggle":
		err = camToggle(os.Args[1:])
	default:
		err = recordToggle(os.Args[1:])
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", name, err)
		os.Exit(1)
	}
}

// $XDG_RUNTIME_DIR, or /tmp without it
func runtimeDir() string {
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return dir
	}
	return "/tmp"
}

// Each record-status (one per bar: waybar runs one for each screen) leaves a
// file here named after its pid, so record-toggle can wake them all
func barsDir() string {
	return filepath.Join(runtimeDir(), "record-status")
}

// Wakes every bar's record-status, so it shows the change at once
func wakeBars() {
	entries, _ := os.ReadDir(barsDir())
	for _, entry := range entries {
		if pid, err := strconv.Atoi(entry.Name()); err == nil {
			syscall.Kill(pid, syscall.SIGUSR1)
		}
	}
}

// Read instead of running pgrep and ps; the tests point it elsewhere
var procRoot = "/proc"

// Whether wf-recorder is running
func recording() bool {
	_, ok := recordingFor()
	return ok
}

// How many seconds the oldest wf-recorder has been running, like
// `ps -o etimes= -p "$(pgrep -ox wf-recorder)"`
func recordingFor() (secs int, ok bool) {
	entries, _ := os.ReadDir(procRoot)
	oldest := -1.0 // its start, in seconds after boot
	for _, entry := range entries {
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue // not a process
		}
		dir := filepath.Join(procRoot, entry.Name())
		comm, err := os.ReadFile(filepath.Join(dir, "comm"))
		if err != nil || strings.TrimSpace(string(comm)) != "wf-recorder" {
			continue
		}
		if start, ok := startTime(dir); ok && (oldest < 0 || start < oldest) {
			oldest = start
		}
	}
	if oldest < 0 {
		return 0, false
	}

	// The first number in /proc/uptime: seconds since boot
	uptime, err := os.ReadFile(filepath.Join(procRoot, "uptime"))
	if err != nil {
		return 0, false
	}
	fields := strings.Fields(string(uptime))
	if len(fields) == 0 {
		return 0, false
	}
	now, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, false
	}
	return int(now - oldest), true
}

// When a process started, in seconds after boot: the 22nd field of
// /proc/<pid>/stat, in clock ticks (always 100 a second there)
func startTime(dir string) (float64, bool) {
	stat, err := os.ReadFile(filepath.Join(dir, "stat"))
	if err != nil {
		return 0, false
	}
	// The 2nd field is the name in brackets, which can hold spaces: count
	// from after it, where the 3rd field starts
	s := string(stat)
	fields := strings.Fields(s[strings.LastIndexByte(s, ')')+1:])
	if len(fields) < 20 {
		return 0, false
	}
	ticks, err := strconv.ParseFloat(fields[22-3], 64)
	if err != nil {
		return 0, false
	}
	return ticks / 100, true
}
