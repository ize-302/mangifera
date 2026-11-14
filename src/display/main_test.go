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

// Stand-ins for mmsg and wlr-randr, first in PATH. They print the files
// written with setMonitors, setWatch and setDisplays, and log every other
// call
type fake struct {
	t   *testing.T
	dir string
}

func newFake(t *testing.T) *fake {
	f := &fake{t: t, dir: t.TempDir()}
	d := f.dir
	f.script("mmsg", `case "$1 $2" in
"get all-monitors") cat `+d+`/monitors ;;
"watch all-monitors") cat `+d+`/watch 2>/dev/null; exit 0 ;;
*) echo "mmsg $*" >> `+d+`/log ;;
esac`)
	f.script("wlr-randr", `case "$1" in
--json) cat `+d+`/displays ;;
*) echo "wlr-randr $*" >> `+d+`/log ;;
esac`)
	t.Setenv("PATH", d+":/usr/bin")
	return f
}

func (f *fake) script(name, body string) {
	if err := os.WriteFile(filepath.Join(f.dir, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
		f.t.Fatal(err)
	}
}

// `mmsg get all-monitors` JSON for these display names
func monitorsJSON(names ...string) string {
	var list []string
	for _, name := range names {
		list = append(list, fmt.Sprintf(`{"name":%q,"active":false,"tags":[]}`, name))
	}
	return `{"monitors":[` + strings.Join(list, ",") + `]}`
}

func (f *fake) setMonitors(names ...string) {
	os.WriteFile(filepath.Join(f.dir, "monitors"), []byte(monitorsJSON(names...)+"\n"), 0o644)
}

func (f *fake) setWatch(lines ...string) {
	os.WriteFile(filepath.Join(f.dir, "watch"), []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

// wlr-randr --json for these display names
func (f *fake) setDisplays(names ...string) {
	var list []string
	for _, name := range names {
		list = append(list, fmt.Sprintf(`{"name":%q,"enabled":true,"modes":[]}`, name))
	}
	os.WriteFile(filepath.Join(f.dir, "displays"), []byte("["+strings.Join(list, ",")+"]\n"), 0o644)
}

func (f *fake) check(want ...string) {
	f.t.Helper()
	data, _ := os.ReadFile(filepath.Join(f.dir, "log"))
	var got []string
	if len(data) > 0 {
		got = strings.Split(strings.TrimSpace(string(data)), "\n")
	}
	if !slices.Equal(got, want) {
		f.t.Errorf("ran %q, want %q", got, want)
	}
}

func TestIsInternal(t *testing.T) {
	for name, want := range map[string]bool{
		"eDP-1": true, "eDP-2": true, "LVDS-1": true, "DSI-1": true,
		"HDMI-A-1": false, "DP-2": false, "DP-eDP": false,
	} {
		if got := isInternal(name); got != want {
			t.Errorf("isInternal(%q) = %v", name, got)
		}
	}
}

// At login with an external display: focuses it, and starts the command
// there, in a session of its own
func TestPrimaryAtLogin(t *testing.T) {
	f := newFake(t)
	f.setMonitors("eDP-1", "HDMI-A-1")
	started := filepath.Join(f.dir, "started")
	// Writes its pid and its session's id
	f.script("app", `echo "$$ $(ps -o sid= -p $$)" > `+started+`.tmp; mv `+started+`.tmp `+started)

	if err := primaryOutput([]string{"app"}); err != nil {
		t.Fatal(err)
	}
	f.check("mmsg dispatch focusmon,HDMI-A-1")

	var data []byte
	for range 100 {
		if data, _ = os.ReadFile(started); len(data) > 0 {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	fields := strings.Fields(string(data))
	if len(fields) != 2 || fields[0] != fields[1] {
		t.Errorf("app wrote %q, want it to lead its own session", data)
	}
}

// Only the laptop's screen: it gets the focus
func TestPrimaryLaptopOnly(t *testing.T) {
	f := newFake(t)
	f.setMonitors("eDP-1")
	primaryOutput(nil)
	f.check("mmsg dispatch focusmon,eDP-1")
}

// Plugging displays in and out while it follows them
func TestPrimaryFollows(t *testing.T) {
	f := newFake(t)
	f.setMonitors("eDP-1")
	f.setWatch(
		// Nothing changed
		monitorsJSON("eDP-1"),
		// Plugged in: focused
		monitorsJSON("eDP-1", "HDMI-A-1"),
		// Another one: focused
		monitorsJSON("eDP-1", "HDMI-A-1", "DP-2"),
		// One unplugged, another left: nothing
		monitorsJSON("eDP-1", "DP-2"),
		// The last one unplugged: back to the laptop's
		monitorsJSON("eDP-1"),
		// Not JSON: skipped
		"oops",
		// Two at once: the first by name
		monitorsJSON("eDP-1", "DP-3", "DP-1"),
	)
	if err := primaryOutput(nil); err != nil {
		t.Fatal(err)
	}
	f.check(
		"mmsg dispatch focusmon,eDP-1",
		"mmsg dispatch focusmon,HDMI-A-1",
		"mmsg dispatch focusmon,DP-2",
		"mmsg dispatch focusmon,eDP-1",
		"mmsg dispatch focusmon,DP-1",
	)
}

func TestPrimaryMmsgFails(t *testing.T) {
	f := newFake(t)
	f.script("mmsg", "exit 1")
	if err := primaryOutput([]string{"app"}); err == nil {
		t.Error("no error")
	}
}

func TestLaptopScreen(t *testing.T) {
	for arg, flag := range map[string]string{"on": "--on", "off": "--off"} {
		f := newFake(t)
		f.setDisplays("eDP-1", "HDMI-A-1", "LVDS-1")
		if err := laptopScreen([]string{arg}); err != nil {
			t.Fatal(err)
		}
		f.check("wlr-randr --output eDP-1 "+flag, "wlr-randr --output LVDS-1 "+flag)
	}
}

// "lid" turns it off only while the lid is closed
func TestLid(t *testing.T) {
	old := lidStates
	t.Cleanup(func() { lidStates = old })
	lid := filepath.Join(t.TempDir(), "LID0")
	os.MkdirAll(lid, 0o755)
	lidStates = filepath.Join(filepath.Dir(lid), "*", "state")

	f := newFake(t)
	f.setDisplays("eDP-1")
	os.WriteFile(filepath.Join(lid, "state"), []byte("state:      open\n"), 0o644)
	laptopScreen([]string{"lid"})
	f.check()

	os.WriteFile(filepath.Join(lid, "state"), []byte("state:      closed\n"), 0o644)
	laptopScreen([]string{"lid"})
	f.check("wlr-randr --output eDP-1 --off")
}

// No lid (a desktop): nothing
func TestNoLid(t *testing.T) {
	old := lidStates
	t.Cleanup(func() { lidStates = old })
	lidStates = filepath.Join(t.TempDir(), "*", "state")
	f := newFake(t)
	f.setDisplays("eDP-1")
	laptopScreen([]string{"lid"})
	f.check()
}

func TestLaptopUsage(t *testing.T) {
	for _, args := range [][]string{nil, {"dim"}} {
		if err := laptopScreen(args); err == nil || err.Error() != "usage: laptop-screen on|off|lid" {
			t.Errorf("%q: %v", args, err)
		}
	}
}
