// mango-reload: reloads mango's and waybar's config, and says whether
// mango's worked. Super+Shift+R runs it (config/mango/config.conf); the
// commands are too long for a line there.
//
// Quickshell isn't restarted: it reloads its own QML when a file changes,
// and starting it again took seconds.
package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

func main() {
	restartWaybar()

	// The logo is from mangowm.github.io
	home, _ := os.UserHomeDir()
	logo := filepath.Join(home, ".local/share/mangifera/mango.svg")
	if reloadMango() {
		exec.Command("notify-send", "-a", "mango", "-i", logo, "-t", "2000", "Config reloaded").Run()
	} else {
		exec.Command("notify-send", "-a", "mango", "-i", logo, "-u", "critical", "Config reload failed").Run()
	}
}

// Waybar reads its config only at start. Restarted, not reloaded in place
// with SIGUSR2: that segfaulted when mango's reload changed the screens.
// The new one starts in a session of its own, like setsid -f, with its
// output dropped
func restartWaybar() {
	exec.Command("pkill", "-x", "waybar").Run()
	cmd := exec.Command("waybar")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if cmd.Start() == nil {
		cmd.Process.Release()
	}
}

// Whether mango says its reload worked: {"success":true,...}. Its answer
// counts, not how mmsg exits
func reloadMango() bool {
	out, _ := exec.Command("mmsg", "dispatch", "reload_config").Output()
	return strings.Contains(string(out), `"success":true`)
}
