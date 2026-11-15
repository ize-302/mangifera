// terminal [--class NAME] [--cwd DIR] [--] [COMMAND [ARG...]]: opens your
// terminal, running COMMAND in it when given, else your shell. mango's
// Super+Return, the app launcher, Thunar's actions and btop-toggle all open
// terminals through this, so none of them names one.
//
// Your terminal is $TERMINAL (set it with env=TERMINAL,<name> in
// ~/.config/mango/local.conf). A path or arguments after the name are fine:
// TERMINAL="foot -o font=mono". When $TERMINAL isn't set, or isn't installed,
// it's the first installed one of the terminals below.
//
// Each terminal takes these options with different flags, and the list below
// knows them. A $TERMINAL that isn't in the list still works: it's started in
// DIR and runs COMMAND with -e, which most terminals take. It can't be given
// a class, though, so --class (btop's scratchpad needs one) uses the list.
//
// --class NAME  the window's app_id, which mango's window rules match
// --cwd DIR     the folder the terminal starts in
//
// install.sh builds this into ~/.local/bin/terminal (see build.sh).
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// How one terminal takes each option
type terminal struct {
	name  string
	sub   []string // a subcommand first, like wezterm's start
	class func(string) []string
	cwd   func(string) []string
	run   []string // before COMMAND, like -e
}

// In order of preference when $TERMINAL isn't set
var terminals = []terminal{
	{
		name:  "foot",
		class: func(c string) []string { return []string{"--app-id=" + c} },
		cwd:   func(d string) []string { return []string{"--working-directory=" + d} },
	},
	{
		name:  "kitty",
		class: func(c string) []string { return []string{"--class=" + c} },
		cwd:   func(d string) []string { return []string{"--directory=" + d} },
	},
	{
		name:  "alacritty",
		class: func(c string) []string { return []string{"--class", c} },
		cwd:   func(d string) []string { return []string{"--working-directory", d} },
		run:   []string{"-e"},
	},
	{
		name:  "wezterm",
		sub:   []string{"start"},
		class: func(c string) []string { return []string{"--class", c} },
		cwd:   func(d string) []string { return []string{"--cwd", d} },
		run:   []string{"--"},
	},
	{
		name:  "ghostty",
		class: func(c string) []string { return []string{"--class=" + c} },
		cwd:   func(d string) []string { return []string{"--working-directory=" + d} },
		run:   []string{"-e"},
	},
}

// What to open
type request struct {
	class   string
	cwd     string
	command []string
}

func main() {
	req, err := parseArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, "terminal:", err)
		fmt.Fprintln(os.Stderr, "usage: terminal [--class NAME] [--cwd DIR] [--] [COMMAND [ARG...]]")
		os.Exit(2)
	}
	argv, err := commandLine(os.Getenv("TERMINAL"), req, isInstalled)
	if err != nil {
		fmt.Fprintln(os.Stderr, "terminal:", err)
		os.Exit(1)
	}
	if req.cwd != "" {
		// Also for a terminal without a flag for it: it starts where it's run
		if err := os.Chdir(req.cwd); err != nil {
			fmt.Fprintln(os.Stderr, "terminal:", err)
			os.Exit(1)
		}
	}
	path, err := exec.LookPath(argv[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, "terminal:", err)
		os.Exit(127)
	}
	// Becomes the terminal, so it's this process mango sees
	err = syscall.Exec(path, argv, os.Environ())
	fmt.Fprintln(os.Stderr, "terminal:", err)
	os.Exit(126)
}

// Options come first; COMMAND starts at the first other word, or after --
func parseArgs(args []string) (request, error) {
	var req request
	for len(args) > 0 {
		arg := args[0]
		switch {
		case arg == "--":
			req.command = args[1:]
			return req, nil
		case arg == "--class" || arg == "--cwd":
			if len(args) < 2 || args[1] == "" {
				return req, fmt.Errorf("%s needs a value", arg)
			}
			if arg == "--class" {
				req.class = args[1]
			} else {
				req.cwd = args[1]
			}
			args = args[2:]
		case strings.HasPrefix(arg, "--class="):
			req.class = strings.TrimPrefix(arg, "--class=")
			args = args[1:]
		case strings.HasPrefix(arg, "--cwd="):
			req.cwd = strings.TrimPrefix(arg, "--cwd=")
			args = args[1:]
		case strings.HasPrefix(arg, "-"):
			return req, fmt.Errorf("unknown option %s", arg)
		default:
			req.command = args
			return req, nil
		}
	}
	return req, nil
}

// The terminal's command line for the request, from $TERMINAL (env) or the
// first installed terminal in the list
func commandLine(env string, req request, installed func(string) bool) ([]string, error) {
	fields := strings.Fields(env)
	// TERMINAL=terminal would start this again, forever
	if len(fields) > 0 && filepath.Base(fields[0]) == "terminal" {
		fmt.Fprintln(os.Stderr, "terminal: $TERMINAL is this launcher itself; set it to your terminal")
		fields = nil
	}
	if len(fields) > 0 {
		name := filepath.Base(fields[0])
		switch term, known := find(name); {
		case !installed(fields[0]):
			fmt.Fprintf(os.Stderr, "terminal: $TERMINAL is %q, which isn't installed; trying %s\n", env, names())
		case known:
			return build(fields, term, req), nil
		case req.class != "":
			fmt.Fprintf(os.Stderr, "terminal: $TERMINAL is %q, which can't be given a class; trying %s\n", env, names())
		default:
			// An unknown terminal: it starts in DIR anyway, and most take -e
			argv := append([]string{}, fields...)
			if len(req.command) > 0 {
				argv = append(append(argv, "-e"), req.command...)
			}
			return argv, nil
		}
	}
	for _, term := range terminals {
		if installed(term.name) {
			return build([]string{term.name}, term, req), nil
		}
	}
	return nil, fmt.Errorf("no terminal found: set $TERMINAL or install %s", names())
}

// base is the terminal and any arguments of its own from $TERMINAL
func build(base []string, term terminal, req request) []string {
	argv := append([]string{}, base...)
	argv = append(argv, term.sub...)
	if req.class != "" {
		argv = append(argv, term.class(req.class)...)
	}
	if req.cwd != "" {
		argv = append(argv, term.cwd(req.cwd)...)
	}
	if len(req.command) > 0 {
		argv = append(append(argv, term.run...), req.command...)
	}
	return argv
}

func find(name string) (terminal, bool) {
	for _, term := range terminals {
		if term.name == name {
			return term, true
		}
	}
	return terminal{}, false
}

// name is a command name or a path
func isInstalled(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func names() string {
	var list []string
	for _, term := range terminals {
		list = append(list, term.name)
	}
	return strings.Join(list[:len(list)-1], ", ") + " or " + list[len(list)-1]
}
