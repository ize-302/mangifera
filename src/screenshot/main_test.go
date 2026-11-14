package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// satty runs this test binary with --copy (see edit): do what screenshot
// would, instead of running the tests
func TestMain(m *testing.M) {
	if len(os.Args) > 1 && os.Args[1] == "--copy" {
		if err := copyImage(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}

// satty stand-in bodies: saves what it's given as shot.png, or copies it with
// its --copy-command, as Enter and Ctrl+C do
const (
	sattySaves = `for arg; do [ "$prev" = --output-filename ] && out=$arg; prev=$arg; done
cat > "$(dirname "$out")/shot.png"`
	sattyCopies = `for arg; do [ "$prev" = --copy-command ] && copy=$arg; prev=$arg; done
$copy`
)

// Stand-ins for the programs screenshot runs. Each logs "name args" and then
// runs its body. By default nothing is being picked, slurp picks an area,
// satty saves what it's given as shot.png, and the notification is clicked.
var defaults = map[string]string{
	"pkill":       "exit 1",
	"slurp":       "echo '10,20 30x40'",
	"grim":        "echo PNG",
	"satty":       sattySaves,
	"notify-send": "echo default",
	"xdg-open":    "",
	"gdbus":       "",
	// Saves what it's given in HOME
	"wl-copy": `cat > "$HOME/clipboard"`,
}

// Puts the stand-ins, with the given bodies replacing the defaults, first in
// PATH (then /usr/bin, for cat and dirname), and HOME in a temp folder. Returns the screenshot folder and a
// function that reads the log.
func fake(t *testing.T, bodies map[string]string) (dir string, log func() []string) {
	home := t.TempDir()
	bin := t.TempDir()
	logFile := filepath.Join(bin, "log")
	for name, body := range defaults {
		if b, ok := bodies[name]; ok {
			body = b
		}
		script := "#!/bin/sh\necho \"" + name + " $*\" >> " + logFile + "\n" + body + "\n"
		if err := os.WriteFile(filepath.Join(bin, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+":/usr/bin")
	t.Setenv("HOME", home)
	return filepath.Join(home, "Pictures", "Screenshots"), func() []string {
		got, _ := os.ReadFile(logFile)
		return strings.Split(strings.TrimSpace(string(got)), "\n")
	}
}

// satty's command line, as logged
func sattyLine(dir string) string {
	self, _ := os.Executable()
	return "satty --filename - --output-filename " + filepath.Join(dir, "%Y-%m-%d_%H-%M-%S.png") +
		" --copy-command " + self + " --copy"
}

func check(t *testing.T, got, want []string) {
	t.Helper()
	if !slices.Equal(got, want) {
		t.Errorf("ran:\n  %s\nwant:\n  %s", strings.Join(got, "\n  "), strings.Join(want, "\n  "))
	}
}

func TestSaveAndOpen(t *testing.T) {
	dir, log := fake(t, nil)
	if err := run(); err != nil {
		t.Fatal(err)
	}
	shot := filepath.Join(dir, "shot.png")
	check(t, log(), []string{
		"pkill -x slurp",
		"slurp -o",
		"grim -g 10,20 30x40 -",
		sattyLine(dir),
		"notify-send -a Screenshot -i " + shot + " --action=default=Open --action=folder=Show in folder --wait Screenshot saved shot.png",
		"xdg-open " + shot,
	})
	// What grim printed reached satty
	if got, _ := os.ReadFile(shot); string(got) != "PNG\n" {
		t.Errorf("saved %q, want grim's output", got)
	}
}

func TestShowInFolder(t *testing.T) {
	dir, log := fake(t, map[string]string{"notify-send": "echo folder"})
	run()
	got := log()
	want := "gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 --method org.freedesktop.FileManager1.ShowItems ['file://" + filepath.Join(dir, "shot.png") + "']" // then "", which the log trims
	if got[len(got)-1] != want {
		t.Errorf("last ran %q, want %q", got[len(got)-1], want)
	}
}

// A second press while slurp is picking only stops it
func TestCancelPick(t *testing.T) {
	_, log := fake(t, map[string]string{"pkill": "exit 0"})
	run()
	check(t, log(), []string{"pkill -x slurp"})
}

// Escape in slurp
func TestEscape(t *testing.T) {
	_, log := fake(t, map[string]string{"slurp": "exit 1"})
	if err := run(); err != nil {
		t.Error(err)
	}
	check(t, log(), []string{"pkill -x slurp", "slurp -o"})
}

// satty closed without saving: no notification, even with older screenshots
// in the folder
func TestNotSaved(t *testing.T) {
	dir, log := fake(t, map[string]string{"satty": "cat > /dev/null"})
	os.MkdirAll(dir, 0o755)
	old := filepath.Join(dir, "old.png")
	os.WriteFile(old, nil, 0o644)
	hourAgo := time.Now().Add(-time.Hour)
	os.Chtimes(old, hourAgo, hourAgo)

	if err := run(); err != nil {
		t.Error(err)
	}
	if got := log(); got[len(got)-1] != sattyLine(dir) {
		t.Errorf("ran %q after satty", got[len(got)-1])
	}
}

// The notification closed without a click
func TestDismissed(t *testing.T) {
	_, log := fake(t, map[string]string{"notify-send": ""})
	run()
	if got := log(); !strings.HasPrefix(got[len(got)-1], "notify-send ") {
		t.Errorf("ran %q after the notification", got[len(got)-1])
	}
}

func TestGrimFails(t *testing.T) {
	_, log := fake(t, map[string]string{"grim": "exit 1"})
	if err := run(); err == nil {
		t.Error("no error")
	}
	if got := log(); got[len(got)-1] != "grim -g 10,20 30x40 -" {
		t.Errorf("ran %q after grim failed", got[len(got)-1])
	}
}

// Ctrl+C in satty: the image reaches wl-copy, and the notification says it
// was copied
func TestCopy(t *testing.T) {
	dir, log := fake(t, map[string]string{"satty": sattyCopies})
	if err := run(); err != nil {
		t.Fatal(err)
	}
	got := log()
	check(t, got[len(got)-3:], []string{
		sattyLine(dir),
		"wl-copy ",
		"notify-send -a Screenshot Screenshot copied Paste it with Ctrl+V",
	})
	if clipboard, _ := os.ReadFile(filepath.Join(os.Getenv("HOME"), "clipboard")); string(clipboard) != "PNG\n" {
		t.Errorf("copied %q, want grim's output", clipboard)
	}
	marker := filepath.Join(os.TempDir(), fmt.Sprintf("screenshot-%d-copied", os.Getpid()))
	if _, err := os.Stat(marker); err == nil {
		t.Errorf("left %s behind", marker)
	}
}

// Copied and then saved: the saved file's notification
func TestCopyThenSave(t *testing.T) {
	dir, log := fake(t, map[string]string{"satty": sattyCopies + "\n" + sattySaves})
	run()
	got := log()
	if want := "xdg-open " + filepath.Join(dir, "shot.png"); got[len(got)-1] != want {
		t.Errorf("last ran %q, want %q", got[len(got)-1], want)
	}
}
