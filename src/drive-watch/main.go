// drive-watch: notices external drives (USB sticks, SD cards, USB disks,
// discs) as they're plugged in. mango starts it at login
// (config/mango/config.conf).
//
// When a drive shows up it mounts the drive's filesystems through udisks and
// notifies, with buttons to open the drive in Files or eject it. Unplugging
// a drive notifies too. Drives already there at login are left alone.
//
// udevadm says when a block device changes; lsblk says what's there now.
// Reading lsblk's output is in drives.go.
package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// How long it waits after a udev event for the rest of a drive's events
// (a disk and its partitions come one by one)
const settle = 700 * time.Millisecond

func main() {
	if err := watch(); err != nil {
		fmt.Fprintln(os.Stderr, "drive-watch:", err)
		os.Exit(1)
	}
}

func watch() error {
	cmd := exec.Command("udevadm", "monitor", "--udev", "--subsystem-match=block")
	out, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("udevadm: %w", err)
	}

	w := &watcher{ejected: map[string]bool{}}
	w.known, _ = scan()

	// Each event (re)starts the timer, so a burst of them rescans once
	var timer *time.Timer
	lines := bufio.NewScanner(out)
	for lines.Scan() {
		if !strings.HasSuffix(lines.Text(), "(block)") {
			continue
		}
		if timer == nil {
			timer = time.AfterFunc(settle, w.rescan)
		} else {
			timer.Reset(settle)
		}
	}
	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("udevadm: %w", err)
	}
	return lines.Err()
}

type watcher struct {
	mu sync.Mutex
	// The drives seen last time, by disk path
	known map[string]drive
	// Disks drive-watch ejected, so pulling them out doesn't notify again
	ejected map[string]bool
}

// Compares what's plugged in now with last time, and acts on the difference
func (w *watcher) rescan() {
	now, err := scan()
	if err != nil {
		fmt.Fprintln(os.Stderr, "drive-watch:", err)
		return
	}
	w.mu.Lock()
	added, removed := diff(w.known, now)
	w.known = now
	for _, d := range added {
		delete(w.ejected, d.Disk)
	}
	var unexpected []drive
	for _, d := range removed {
		if !w.ejected[d.Disk] {
			unexpected = append(unexpected, d)
		}
		delete(w.ejected, d.Disk)
	}
	w.mu.Unlock()

	for _, d := range added {
		go w.connected(d)
	}
	for _, d := range unexpected {
		go disconnected(d)
	}
}

// Mounts the new drive and notifies. The notification's buttons open or
// eject it
func (w *watcher) connected(d drive) {
	var failed []string
	for _, f := range d.Filesystems {
		if f.Mountpoint != "" || !mountable(f) {
			continue
		}
		if err := udisksctl("mount", "-b", f.Path); err != nil {
			failed = append(failed, f.Path)
		}
	}
	// Read the drive again for where udisks mounted it
	if now, err := scan(); err == nil {
		if fresh, ok := now[d.Disk]; ok {
			d = fresh
		}
	}

	place := d.mountpoint()
	body := d.Size
	switch {
	case place != "":
		body += " · " + place
	case d.encrypted():
		body += " · encrypted: unlock it in Files"
	case len(failed) > 0:
		body += " · couldn't be mounted"
	}

	answer := notify("normal", "drive-removable-media", d.Name+" connected", body,
		"--action=default=Open", "--action=eject=Eject", "--wait")
	switch answer {
	case "default":
		if place != "" {
			exec.Command("xdg-open", place).Start()
		} else {
			exec.Command("thunar").Start()
		}
	case "eject":
		w.eject(d.Disk)
	}
}

// Unmounts every filesystem on the disk, then powers it off when it's one
// that can be (a USB stick or disk, not a card in a reader)
func (w *watcher) eject(disk string) {
	now, err := scan()
	d, ok := now[disk]
	if err != nil || !ok {
		return // Already gone
	}
	for _, f := range d.Filesystems {
		if f.Mountpoint == "" {
			continue
		}
		if err := udisksctl("unmount", "-b", f.Path); err != nil {
			notify("normal", "dialog-warning", "Couldn't eject "+d.Name,
				"Something is still using it. Close it and try again.")
			return
		}
	}
	w.mu.Lock()
	w.ejected[disk] = true
	w.mu.Unlock()
	if d.PowerOff {
		udisksctl("power-off", "-b", disk)
	}
	notify("low", "media-eject", d.Name+" ejected", "It's safe to unplug.")
}

// Notifies that a drive was unplugged, or ejected from Files
func disconnected(d drive) {
	notify("low", "drive-removable-media", d.Name+" removed", "")
}

// Runs udisksctl without asking for a password, in English
func udisksctl(args ...string) error {
	cmd := exec.Command("udisksctl", append(args, "--no-user-interaction")...)
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintf(os.Stderr, "drive-watch: udisksctl %s: %s\n", strings.Join(args, " "), strings.TrimSpace(string(out)))
	}
	return err
}

// Sends a notification and returns the name of the button clicked, when
// called with --wait. It gives up waiting after an hour
func notify(urgency, icon, summary, body string, extra ...string) string {
	args := append([]string{"-a", "Drives", "-u", urgency, "-i", icon}, extra...)
	args = append(args, summary)
	if body != "" {
		args = append(args, body)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Hour)
	defer cancel()
	out, _ := exec.CommandContext(ctx, "notify-send", args...).Output()
	return strings.TrimSpace(string(out))
}
