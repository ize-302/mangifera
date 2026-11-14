package main

// primary-output [COMMAND...]: focuses the external display if any, else the
// laptop's, then runs COMMAND there. Keeps following displays as they are
// plugged in and out: a new one gets the focus, and when the last external
// one goes, the laptop's does.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"syscall"
)

func primaryOutput(command []string) error {
	out, err := exec.Command("mmsg", "get", "all-monitors").Output()
	if err != nil {
		return fmt.Errorf("mmsg: %w", err)
	}
	names, _ := monitorNames(out)
	focus(primary(names))
	if len(command) > 0 {
		start(command)
	}

	// mmsg prints every display as one line of JSON whenever any changes
	watch := exec.Command("mmsg", "watch", "all-monitors")
	events, err := watch.StdoutPipe()
	if err != nil {
		return err
	}
	if err := watch.Start(); err != nil {
		return fmt.Errorf("mmsg: %w", err)
	}
	known := externals(names)
	lines := bufio.NewScanner(events)
	lines.Buffer(nil, 16<<20)
	for lines.Scan() {
		names, err := monitorNames(lines.Bytes())
		if err != nil {
			continue
		}
		now := externals(names)
		if slices.Equal(now, known) {
			continue
		}
		if added := firstAdded(known, now); added != "" {
			focus(added)
		} else if len(now) == 0 {
			focus(primary(names)) // the last external one went
		}
		known = now
	}
	return watch.Wait()
}

// The display names in `mmsg get all-monitors` JSON
func monitorNames(data []byte) ([]string, error) {
	var m struct {
		Monitors []struct {
			Name string `json:"name"`
		} `json:"monitors"`
	}
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	var names []string
	for _, mon := range m.Monitors {
		names = append(names, mon.Name)
	}
	return names, nil
}

// The first external display, else the first one, else ""
func primary(names []string) string {
	if ext := externals(names); len(ext) > 0 {
		return ext[0]
	}
	if len(names) > 0 {
		return names[0]
	}
	return ""
}

// The first by name of those in now but not in before, or ""
func firstAdded(before, now []string) string {
	first := ""
	for _, name := range now {
		if !slices.Contains(before, name) && (first == "" || name < first) {
			first = name
		}
	}
	return first
}

func focus(name string) {
	if name != "" {
		exec.Command("mmsg", "dispatch", "focusmon,"+name).Run()
	}
}

// Starts the command in a session of its own, like setsid -f, so it lives
// on by itself; its output is dropped
func start(command []string) {
	cmd := exec.Command(command[0], command[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "primary-output:", err) // and keep following
		return
	}
	cmd.Process.Release()
}
