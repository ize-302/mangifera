// btop-toggle: shows or hides btop as mango's named scratchpad. Run by the
// bar's CPU and memory modules.
//
// btop opens in $TERMINAL when it's one of the terminals below, else in the
// first of them that's installed. mango finds the scratchpad by its app_id,
// "btop" (see the window rule in config/mango/config.conf), and each
// terminal sets that with a different flag.
//
// install.sh builds this into ~/.local/bin/btop-toggle (see build.sh).
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// A terminal and its arguments to run btop with app_id "btop"
type terminal struct {
	name string
	args []string
}

// In order of preference when $TERMINAL isn't set
var terminals = []terminal{
	{"alacritty", []string{"--class", "btop", "-e", "btop"}},
	{"kitty", []string{"--class", "btop", "btop"}},
	{"foot", []string{"--app-id", "btop", "btop"}},
	{"wezterm", []string{"start", "--class", "btop", "--", "btop"}},
	{"ghostty", []string{"--class=btop", "-e", "btop"}},
}

func main() {
	code := run()
	os.Exit(code)
}

func run() int {
	term, err := pickTerminal(os.Getenv("TERMINAL"), isInstalled)
	if err != nil {
		fmt.Fprintln(os.Stderr, "btop-toggle:", err)
		return 1
	}

	// Toggles the "btop" scratchpad, starting the terminal if it isn't open
	cmd := exec.Command("mmsg", mmsgArgs(term)...)
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
func mmsgArgs(term terminal) []string {
	return append([]string{"dispatch", "toggle_named_scratchpad,btop,none," + term.name}, term.args...)
}

// $TERMINAL when it's one we know (a path or arguments after it are fine),
// else the first installed one
func pickTerminal(env string, installed func(string) bool) (terminal, error) {
	fields := strings.Fields(env)
	if len(fields) > 0 {
		name := filepath.Base(fields[0])
		for _, term := range terminals {
			if term.name == name && installed(name) {
				return term, nil
			}
		}
		fmt.Fprintf(os.Stderr, "btop-toggle: $TERMINAL is %q, which can't open btop as a scratchpad; trying %s\n", env, terminalNames())
	}
	for _, term := range terminals {
		if installed(term.name) {
			return term, nil
		}
	}
	return terminal{}, fmt.Errorf("no terminal for btop: install one of %s", terminalNames())
}

func isInstalled(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func terminalNames() string {
	var list []string
	for _, term := range terminals {
		list = append(list, term.name)
	}
	return strings.Join(list[:len(list)-1], ", ") + " or " + list[len(list)-1]
}
