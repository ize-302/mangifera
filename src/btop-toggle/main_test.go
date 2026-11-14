package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// Puts a stand-in mmsg, and empty stand-ins for the given terminals, alone
// in PATH. mmsg writes its arguments, one per line, to the returned file and
// exits with code.
func fakePath(t *testing.T, code string, terminals ...string) (argsFile string) {
	dir := t.TempDir()
	argsFile = filepath.Join(dir, "args")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + argsFile + "\nexit " + code + "\n"
	if err := os.WriteFile(filepath.Join(dir, "mmsg"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range terminals {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
	return argsFile
}

func readArgs(t *testing.T, argsFile string) string {
	got, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatal("mmsg wasn't run:", err)
	}
	return strings.ReplaceAll(strings.TrimSpace(string(got)), "\n", " ")
}

// With alacritty, the same call the bash script made
func TestAlacritty(t *testing.T) {
	t.Setenv("TERMINAL", "")
	argsFile := fakePath(t, "0", "alacritty", "kitty")
	if code := run(); code != 0 {
		t.Fatalf("exit code %d, want 0", code)
	}
	want := "dispatch toggle_named_scratchpad,btop,none,alacritty --class btop -e btop"
	if got := readArgs(t, argsFile); got != want {
		t.Errorf("mmsg got %q, want %q", got, want)
	}
}

// $TERMINAL wins over the order of the list
func TestTerminalEnv(t *testing.T) {
	t.Setenv("TERMINAL", "/usr/bin/foot -o font=mono")
	argsFile := fakePath(t, "0", "alacritty", "foot")
	run()
	want := "dispatch toggle_named_scratchpad,btop,none,foot --app-id btop btop"
	if got := readArgs(t, argsFile); got != want {
		t.Errorf("mmsg got %q, want %q", got, want)
	}
}

func TestPickTerminal(t *testing.T) {
	tests := []struct {
		env       string
		installed []string
		want      string // "" for an error
	}{
		{"", []string{"alacritty"}, "alacritty"},
		{"", []string{"wezterm", "kitty"}, "kitty"}, // the list's order
		{"kitty", []string{"alacritty", "kitty"}, "kitty"},
		{"wezterm", []string{"alacritty", "wezterm"}, "wezterm"},
		{"kitty", []string{"alacritty"}, "alacritty"}, // $TERMINAL not installed
		{"gnome-terminal", []string{"foot"}, "foot"},  // one we can't use
		{"xterm", nil, ""}, // nothing usable
		{"", nil, ""},
	}
	for _, test := range tests {
		got, err := pickTerminal(test.env, func(name string) bool { return slices.Contains(test.installed, name) })
		if test.want == "" {
			if err == nil {
				t.Errorf("TERMINAL=%q, installed %v: got %q, want an error", test.env, test.installed, got.name)
			}
			continue
		}
		if err != nil || got.name != test.want {
			t.Errorf("TERMINAL=%q, installed %v: got %q, %v; want %q", test.env, test.installed, got.name, err, test.want)
		}
	}
}

// Each terminal starts btop with app_id "btop", which mango's window rule
// (app_id:^btop$) and the scratchpad's name both expect
func TestEveryTerminalSetsAppID(t *testing.T) {
	for _, term := range terminals {
		joined := " " + strings.Join(term.args, " ") + " "
		if !strings.Contains(joined, " btop ") || !strings.HasSuffix(joined, " btop ") {
			t.Errorf("%s: %q doesn't set app_id btop and run btop", term.name, joined)
		}
		if got := mmsgArgs(term)[1]; got != "toggle_named_scratchpad,btop,none,"+term.name {
			t.Errorf("%s: dispatch %q", term.name, got)
		}
	}
}

// mmsg's own exit code comes back, like with bash's exec
func TestExitCode(t *testing.T) {
	t.Setenv("TERMINAL", "")
	fakePath(t, "3", "alacritty")
	if code := run(); code != 3 {
		t.Errorf("exit code %d, want 3", code)
	}
}

func TestMmsgMissing(t *testing.T) {
	t.Setenv("TERMINAL", "")
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "alacritty"), []byte("#!/bin/sh\n"), 0o755)
	t.Setenv("PATH", dir)
	if code := run(); code != 127 {
		t.Errorf("exit code %d, want 127", code)
	}
}

func TestNoTerminal(t *testing.T) {
	t.Setenv("TERMINAL", "")
	fakePath(t, "0")
	if code := run(); code != 1 {
		t.Errorf("exit code %d, want 1", code)
	}
}
