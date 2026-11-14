package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The same calls the bash script made
func TestCameraCall(t *testing.T) {
	tests := map[string]string{
		"":           "toggle",
		"rotate":     "rotate",
		"zoom-in":    "zoomIn",
		"zoom-out":   "zoomOut",
		"zoom-reset": "zoomReset",
		"other":      "toggle",
	}
	for arg, want := range tests {
		if got := cameraCall(arg); got != want {
			t.Errorf("cameraCall(%q) = %q, want %q", arg, got, want)
		}
	}
}

// Runs this test binary as cam-toggle with args, with a stand-in
// ~/.local/bin/launcher-call that logs its arguments and exits with code.
// Returns what launcher-call got, and cam-toggle's exit code.
func runCamToggle(t *testing.T, code string, args ...string) (got string, exitCode int) {
	home := t.TempDir()
	bin := filepath.Join(home, ".local", "bin")
	os.MkdirAll(bin, 0o755)
	log := filepath.Join(home, "log")
	script := "#!/bin/sh\necho \"$*\" > " + log + "\nexit " + code + "\n"
	if err := os.WriteFile(filepath.Join(bin, "launcher-call"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(os.Args[0], args...)
	cmd.Env = append(os.Environ(), "RECORD_RUN=cam-toggle", "HOME="+home)
	cmd.Run()
	out, _ := os.ReadFile(log)
	return strings.TrimSpace(string(out)), cmd.ProcessState.ExitCode()
}

func TestCamToggle(t *testing.T) {
	if got, _ := runCamToggle(t, "0", "zoom-in"); got != "camera zoomIn" {
		t.Errorf("launcher-call got %q, want %q", got, "camera zoomIn")
	}
	if got, _ := runCamToggle(t, "0"); got != "camera toggle" {
		t.Errorf("with no argument, launcher-call got %q, want %q", got, "camera toggle")
	}
}

// launcher-call's exit code comes back, like with bash's exec
func TestCamToggleExitCode(t *testing.T) {
	if _, code := runCamToggle(t, "3"); code != 3 {
		t.Errorf("exit code %d, want 3", code)
	}
}

func TestCamToggleLauncherCallMissing(t *testing.T) {
	cmd := exec.Command(os.Args[0])
	cmd.Env = append(os.Environ(), "RECORD_RUN=cam-toggle", "HOME="+t.TempDir(), "GORACE=atexit_sleep_ms=0")
	out, _ := cmd.CombinedOutput()
	if code := cmd.ProcessState.ExitCode(); code != 1 {
		t.Errorf("exit code %d, want 1", code)
	}
	if !strings.HasPrefix(string(out), "cam-toggle: ") {
		t.Errorf("printed %q", out)
	}
}
