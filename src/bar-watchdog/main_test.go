package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"
)

// A made-up /proc, and stand-ins for logger, notify-send and waybar that log
// their calls. wait, between the two measures, runs between() and logs
// "wait"; kill logs too
type rig struct {
	t       *testing.T
	proc    string
	log     string
	between func()
}

func newRig(t *testing.T) *rig {
	r := &rig{t: t, proc: t.TempDir()}
	bin := t.TempDir()
	r.log = filepath.Join(bin, "log")
	for _, name := range []string{"logger", "notify-send", "waybar"} {
		script := "#!/bin/sh\necho \"" + name + " $*\" >> " + r.log + "\n"
		os.WriteFile(filepath.Join(bin, name), []byte(script), 0o755)
	}
	t.Setenv("PATH", bin+":/usr/bin")

	oldRoot, oldWait, oldKill := procRoot, wait, kill
	t.Cleanup(func() { procRoot, wait, kill = oldRoot, oldWait, oldKill })
	procRoot = r.proc
	wait = func(d time.Duration) {
		r.note(fmt.Sprintf("wait %v", d))
		if d == period && r.between != nil {
			r.between()
			r.between = nil
		}
	}
	kill = func(pid int, sig syscall.Signal) error {
		r.note(fmt.Sprintf("kill %d %v", pid, sig))
		return nil
	}
	return r
}

func (r *rig) note(line string) {
	f, err := os.OpenFile(r.log, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		r.t.Fatal(err)
	}
	fmt.Fprintln(f, line)
	f.Close()
}

// Writes a process's stat, or a thread's when tid isn't 0: started at start
// ticks after boot, having used user + system ticks
func (r *rig) stat(pid, tid int, name string, user, system, start int) {
	dir := filepath.Join(r.proc, fmt.Sprint(pid))
	id := pid
	if tid != 0 {
		dir = filepath.Join(dir, "task", fmt.Sprint(tid))
		id = tid
	}
	os.MkdirAll(dir, 0o755)
	// Fields 3 to 22: state, 10 others, utime, stime, 6 others, starttime
	line := fmt.Sprintf("%d (%s) S 1 1 1 0 -1 0 0 0 0 0 %d %d 0 0 20 0 1 0 %d 0 0\n", id, name, user, system, start)
	if err := os.WriteFile(filepath.Join(dir, "stat"), []byte(line), 0o644); err != nil {
		r.t.Fatal(err)
	}
}

func (r *rig) check(want ...string) {
	r.t.Helper()
	data, _ := os.ReadFile(r.log)
	var got []string
	if len(data) > 0 {
		got = strings.Split(strings.TrimSpace(string(data)), "\n")
	}
	if !slices.Equal(got, want) {
		r.t.Errorf("ran\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// waybar at pid 500, with its main thread and a worker
func (r *rig) waybar(main, worker int) {
	r.stat(500, 0, "waybar", main+worker, 0, 1000)
	r.stat(500, 500, "waybar", main, 0, 1000)
	r.stat(500, 510, "gmain", worker, 0, 1000)
}

// Over half a core for the minute (3000 ticks): logged with the busy
// thread, notified, stopped and started again
func TestRestartsBusyBar(t *testing.T) {
	r := newRig(t)
	r.stat(400, 0, "bash", 0, 0, 10) // another process
	r.waybar(100, 50)
	r.between = func() {
		r.waybar(100+5900, 50+100)                      // the main thread spun: 98%
		r.stat(500, 520, "pool-spawner", 3100, 0, 1500) // a new thread, 51%
		r.stat(500, 0, "waybar", 6000+150+3100, 0, 1000)
	}
	check()
	r.check(
		"wait 1m0s",
		"logger -t bar-watchdog waybar 500 used 151% CPU for 60s, threads: 500 waybar(98%), 520 pool-spawner(51%); restarting",
		"notify-send -a waybar -u low Bar restarted It was using too much CPU.",
		"kill 500 terminated",
		"wait 1s",
	)
	// waybar starts in a session of its own, so it may log a moment later
	for range 100 {
		if data, _ := os.ReadFile(r.log); strings.Contains(string(data), "waybar \n") {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Error("waybar wasn't started")
}

// Exactly half a core is still fine
func TestLeavesBarAtLimit(t *testing.T) {
	r := newRig(t)
	r.waybar(100, 0)
	r.between = func() { r.waybar(3100, 0) }
	check()
	r.check("wait 1m0s")
}

// Busy, but spread over threads none of which used half a core
func TestSpreadOut(t *testing.T) {
	r := newRig(t)
	r.waybar(0, 0)
	r.between = func() { r.waybar(2000, 2000) }
	check()
	r.check(
		"wait 1m0s",
		"logger -t bar-watchdog waybar 500 used 66% CPU for 60s, threads: none; restarting",
		"notify-send -a waybar -u low Bar restarted It was using too much CPU.",
		"kill 500 terminated",
		"wait 1s",
	)
}

// waybar restarted (by mango's reload) during the minute: nothing
func TestBarRestartedMeanwhile(t *testing.T) {
	r := newRig(t)
	r.waybar(0, 0)
	r.between = func() {
		os.RemoveAll(filepath.Join(r.proc, "500"))
		r.stat(600, 0, "waybar", 9000, 0, 7000)
	}
	check()
	r.check("wait 1m0s")
}

// No waybar: it waits the minute and looks again
func TestNoBar(t *testing.T) {
	r := newRig(t)
	r.stat(400, 0, "bash", 9000, 0, 10)
	check()
	r.check("wait 1m0s")
}

// Two waybars: the oldest, like pgrep -o
func TestOldest(t *testing.T) {
	r := newRig(t)
	r.stat(900, 0, "waybar", 0, 0, 300)
	r.stat(700, 0, "waybar", 0, 0, 200)
	r.stat(800, 0, "waybar-helper", 0, 0, 100)
	// A name with a space and a bracket
	r.stat(100, 0, "my) waybar", 0, 0, 50)
	if pid, ok := oldest("waybar"); !ok || pid != 700 {
		t.Errorf("oldest = %d, %v", pid, ok)
	}
	if s, ok := readStat(filepath.Join(r.proc, "100", "stat")); !ok || s.name != "my) waybar" || s.start != 50 {
		t.Errorf("readStat = %+v, %v", s, ok)
	}
}
