package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Puts a stand-in mmsg, and an empty stand-in terminal launcher when asked,
// alone in PATH. mmsg writes its arguments, one per line, to the returned
// file and exits with code.
func fakePath(t *testing.T, code string, launcher bool) (dir, argsFile string) {
	dir = t.TempDir()
	argsFile = filepath.Join(dir, "args")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + argsFile + "\nexit " + code + "\n"
	if err := os.WriteFile(filepath.Join(dir, "mmsg"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	if launcher {
		if err := os.WriteFile(filepath.Join(dir, "terminal"), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
	return dir, argsFile
}

func readArgs(t *testing.T, argsFile string) string {
	got, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatal("mmsg wasn't run:", err)
	}
	return strings.ReplaceAll(strings.TrimSpace(string(got)), "\n", " ")
}

// btop opens through the launcher, with app_id "btop", which mango's window
// rule (app_id:^btop$) and the scratchpad's name both expect
func TestToggle(t *testing.T) {
	dir, argsFile := fakePath(t, "0", true)
	if code := run(); code != 0 {
		t.Fatalf("exit code %d, want 0", code)
	}
	want := "dispatch toggle_named_scratchpad,btop,none," + filepath.Join(dir, "terminal") + " --class btop btop"
	if got := readArgs(t, argsFile); got != want {
		t.Errorf("mmsg got %q, want %q", got, want)
	}
}

// mmsg's own exit code comes back, like with bash's exec
func TestExitCode(t *testing.T) {
	fakePath(t, "3", true)
	if code := run(); code != 3 {
		t.Errorf("exit code %d, want 3", code)
	}
}

func TestMmsgMissing(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "terminal"), []byte("#!/bin/sh\n"), 0o755)
	t.Setenv("PATH", dir)
	if code := run(); code != 127 {
		t.Errorf("exit code %d, want 127", code)
	}
}

func TestNoLauncher(t *testing.T) {
	fakePath(t, "0", false)
	if code := run(); code != 1 {
		t.Errorf("exit code %d, want 1", code)
	}
}
