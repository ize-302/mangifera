// bar-watchdog: restarts waybar when it uses over half a core for a whole
// minute. mango starts it at login (config/mango/config.conf). Twice waybar
// had threads spinning at 100% each for hours, cause unknown; this caps that
// at a minute. Each restart is logged (journalctl -t bar-watchdog) with the
// threads that were busy, and notified, to help find the cause.
package main

import (
	"cmp"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var (
	// How long it measures for. The tests shorten it
	period = time.Minute
	// Waits, for period and for waybar to stop. The tests replace it
	wait = time.Sleep
	// Where processes are listed. The tests move it
	procRoot = "/proc"
	// Stops a process. The tests replace it, as their waybar is made up
	kill = syscall.Kill
)

// Linux counts CPU time in ticks of 1/100 s (getconf CLK_TCK)
const hz = 100

func main() {
	for {
		check()
	}
}

// Measures waybar for a period, and restarts it if it was too busy
func check() {
	pid, found := oldest("waybar")
	before, ok := usage(pid)
	wait(period)
	if !found || !ok {
		return
	}
	after, ok := usage(pid)
	// Restarted, or stopped
	if now, _ := oldest("waybar"); !ok || now != pid {
		return
	}

	ticks := after.total - before.total
	limit := int(period.Seconds() * hz / 2)
	if ticks <= limit {
		return
	}
	exec.Command("logger", "-t", "bar-watchdog", fmt.Sprintf(
		"waybar %d used %d%% CPU for %ds, threads: %s; restarting",
		pid, percent(ticks), int(period.Seconds()), busyThreads(before, after))).Run()
	exec.Command("notify-send", "-a", "waybar", "-u", "low", "Bar restarted", "It was using too much CPU.").Run()
	kill(pid, syscall.SIGTERM)
	wait(time.Second)
	restart()
}

// A share of one core over the period, in %
func percent(ticks int) int {
	return int(float64(ticks) * 100 / period.Seconds() / hz)
}

// Starts waybar in a session of its own, like setsid -f, with its output
// dropped
func restart() {
	cmd := exec.Command("waybar")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "bar-watchdog:", err)
		return
	}
	cmd.Process.Release()
}

// What /proc/PID/stat says about a process or thread
type stat struct {
	name  string
	ticks int // CPU time used so far: user and system
	start int // when it started, in ticks after boot
}

// Reads /proc/.../stat: "PID (NAME) STATE ...", where NAME can hold spaces
// and brackets, so the fields are counted from the last ")"
func readStat(path string) (stat, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return stat{}, false
	}
	open := strings.IndexByte(string(data), '(')
	end := strings.LastIndexByte(string(data), ')')
	if open < 0 || end < open {
		return stat{}, false
	}
	// From field 3 on: utime and stime are fields 14 and 15, starttime 22
	fields := strings.Fields(string(data[end+1:]))
	if len(fields) < 20 {
		return stat{}, false
	}
	utime, err1 := strconv.Atoi(fields[11])
	stime, err2 := strconv.Atoi(fields[12])
	start, err3 := strconv.Atoi(fields[19])
	if err1 != nil || err2 != nil || err3 != nil {
		return stat{}, false
	}
	return stat{string(data[open+1 : end]), utime + stime, start}, true
}

// The oldest process called name, like pgrep -ox
func oldest(name string) (int, bool) {
	entries, _ := os.ReadDir(procRoot)
	pid, first := 0, -1
	for _, entry := range entries {
		n, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		s, ok := readStat(filepath.Join(procRoot, entry.Name(), "stat"))
		if ok && s.name == name && (first < 0 || s.start < first) {
			pid, first = n, s.start
		}
	}
	return pid, first >= 0
}

// A process's CPU time so far, and each of its threads'
type sample struct {
	total   int
	threads map[int]stat
}

func usage(pid int) (sample, bool) {
	dir := filepath.Join(procRoot, strconv.Itoa(pid))
	s, ok := readStat(filepath.Join(dir, "stat"))
	if !ok {
		return sample{}, false
	}
	threads := map[int]stat{}
	entries, _ := os.ReadDir(filepath.Join(dir, "task"))
	for _, entry := range entries {
		tid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		if t, ok := readStat(filepath.Join(dir, "task", entry.Name(), "stat")); ok {
			threads[tid] = t
		}
	}
	return sample{s.ticks, threads}, true
}

// The threads that used over half a core in the period, the busiest first:
// "1234 waybar(98%), 1240 gmain(55%)", or "none" when it was spread out
func busyThreads(before, after sample) string {
	type busy struct {
		tid   int
		name  string
		ticks int
	}
	var list []busy
	for tid, t := range after.threads {
		ticks := t.ticks - before.threads[tid].ticks // all of it if new
		if ticks > int(period.Seconds()*hz/2) {
			list = append(list, busy{tid, t.name, ticks})
		}
	}
	if len(list) == 0 {
		return "none"
	}
	slices.SortFunc(list, func(a, b busy) int {
		return cmp.Or(cmp.Compare(b.ticks, a.ticks), cmp.Compare(a.tid, b.tid))
	})
	var parts []string
	for _, b := range list {
		parts = append(parts, fmt.Sprintf("%d %s(%d%%)", b.tid, b.name, percent(b.ticks)))
	}
	return strings.Join(parts, ", ")
}
