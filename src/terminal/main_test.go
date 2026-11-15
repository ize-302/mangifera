package main

import (
	"slices"
	"strings"
	"testing"
)

func TestParseArgs(t *testing.T) {
	tests := []struct {
		args    []string
		want    request
		wantErr bool
	}{
		{nil, request{}, false},
		{[]string{"nvim", "a b.txt"}, request{command: []string{"nvim", "a b.txt"}}, false},
		{[]string{"--class", "btop", "btop"}, request{class: "btop", command: []string{"btop"}}, false},
		{[]string{"--cwd=/tmp", "--class=x"}, request{class: "x", cwd: "/tmp"}, false},
		// After --, words that look like options are COMMAND's
		{[]string{"--cwd", "/tmp", "--", "ls", "-la"}, request{cwd: "/tmp", command: []string{"ls", "-la"}}, false},
		// And after COMMAND starts, too
		{[]string{"ls", "--class", "x"}, request{command: []string{"ls", "--class", "x"}}, false},
		{[]string{"--class"}, request{}, true},
		{[]string{"--cwd", ""}, request{}, true},
		{[]string{"-e", "ls"}, request{}, true},
	}
	for _, test := range tests {
		got, err := parseArgs(test.args)
		if test.wantErr {
			if err == nil {
				t.Errorf("%q: got %+v, want an error", test.args, got)
			}
			continue
		}
		if err != nil || got.class != test.want.class || got.cwd != test.want.cwd || !slices.Equal(got.command, test.want.command) {
			t.Errorf("%q: got %+v, %v; want %+v", test.args, got, err, test.want)
		}
	}
}

func TestCommandLine(t *testing.T) {
	everything := request{class: "btop", cwd: "/tmp", command: []string{"btop", "-p", "1"}}
	tests := []struct {
		env       string
		installed []string
		req       request
		want      string // "" for an error
	}{
		// Nothing asked: just the terminal
		{"foot", []string{"foot"}, request{}, "foot"},
		{"", []string{"wezterm", "kitty"}, request{}, "kitty"}, // the list's order
		// Each known terminal's flags
		{"foot", []string{"foot"}, everything, "foot --app-id=btop --working-directory=/tmp btop -p 1"},
		{"kitty", []string{"kitty"}, everything, "kitty --class=btop --directory=/tmp btop -p 1"},
		{"alacritty", []string{"alacritty"}, everything, "alacritty --class btop --working-directory /tmp -e btop -p 1"},
		{"wezterm", []string{"wezterm"}, everything, "wezterm start --class btop --cwd /tmp -- btop -p 1"},
		{"ghostty", []string{"ghostty"}, everything, "ghostty --class=btop --working-directory=/tmp -e btop -p 1"},
		// $TERMINAL's own path and arguments are kept, before wezterm's start
		{"/usr/bin/foot -o font=mono", []string{"/usr/bin/foot"}, request{command: []string{"nvim"}}, "/usr/bin/foot -o font=mono nvim"},
		{"wezterm --config-file x", []string{"wezterm"}, request{cwd: "/tmp"}, "wezterm --config-file x start --cwd /tmp"},
		// $TERMINAL not installed: the list
		{"kitty", []string{"alacritty"}, request{}, "alacritty"},
		// Unknown: started as is, COMMAND after -e; no class though
		{"xterm", []string{"xterm", "foot"}, request{cwd: "/tmp", command: []string{"nvim"}}, "xterm -e nvim"},
		{"xterm", []string{"xterm", "foot"}, request{class: "btop"}, "foot --app-id=btop"},
		// Never itself
		{"terminal", []string{"terminal", "kitty"}, request{}, "kitty"},
		{"", nil, request{}, ""},
		{"xterm", []string{"xterm"}, request{class: "btop"}, ""},
	}
	for _, test := range tests {
		installed := func(name string) bool { return slices.Contains(test.installed, name) }
		got, err := commandLine(test.env, test.req, installed)
		if test.want == "" {
			if err == nil {
				t.Errorf("TERMINAL=%q, installed %v: got %q, want an error", test.env, test.installed, got)
			}
			continue
		}
		if err != nil || strings.Join(got, " ") != test.want {
			t.Errorf("TERMINAL=%q, installed %v, %+v: got %q, %v; want %q", test.env, test.installed, test.req, got, err, test.want)
		}
	}
}
