// btop-toggle: shows or hides btop as mango's named scratchpad. Run by the
// bar's CPU and memory modules.
//
// btop opens through the terminal launcher beside this one
// (~/.local/bin/terminal, see src/terminal), so in $TERMINAL. mango finds
// the scratchpad by its app_id, "btop" (see the window rule in
// config/mango/config.conf), which the launcher sets with --class.
//
// install.sh builds this into ~/.local/bin/btop-toggle (see build.sh).
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func main() {
	code := run()
	os.Exit(code)
}

func run() int {
	launcher, err := terminalLauncher()
	if err != nil {
		fmt.Fprintln(os.Stderr, "btop-toggle:", err)
		return 1
	}

	// Toggles the "btop" scratchpad, starting the terminal if it isn't open
	cmd := exec.Command("mmsg", mmsgArgs(launcher)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	err = cmd.Run()

	var exitErr *exec.ExitError
	switch {
	case err == nil:
		return 0
	case errors.As(err, &exitErr):
		return exitErr.ExitCode() // mmsg ran and failed: it said why
	default:
		fmt.Fprintln(os.Stderr, "btop-toggle:", err) // e.g. mmsg isn't installed
		return 127
	}
}

// mmsg dispatch toggle_named_scratchpad,<app_id>,<title>,<command> ...
// The command's first word goes after the last comma, its arguments follow
// as mmsg's own arguments.
func mmsgArgs(launcher string) []string {
	return []string{"dispatch", "toggle_named_scratchpad,btop,none," + launcher, "--class", "btop", "btop"}
}

// The terminal launcher in this program's folder, else the one in PATH
func terminalLauncher() (string, error) {
	if self, err := os.Executable(); err == nil {
		launcher := filepath.Join(filepath.Dir(self), "terminal")
		if info, err := os.Stat(launcher); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return launcher, nil
		}
	}
	launcher, err := exec.LookPath("terminal")
	if err != nil {
		return "", errors.New("no terminal launcher: run ./install.sh to build ~/.local/bin/terminal")
	}
	return launcher, nil
}
