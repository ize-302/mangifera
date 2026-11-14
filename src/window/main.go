// focus-window, move-window and focus-urgent: moving around mango's windows.
//
// One binary, three names: install.sh builds it into
// ~/.local/bin/focus-window, and move-window and focus-urgent are symlinks to
// it. It looks at the name it was run as to know what to do.
//
//	focus-window left|right   Super+H/L and Super+Left/Right
//	move-window left|right    Super+Shift+H/L and Super+Shift+Left/Right
//	focus-urgent              run by mango at login, keeps running
//
// focus-window and move-window are in edge.go, focus-urgent in urgent.go.
// They read mango's state as JSON from mmsg, and change it with
// `mmsg dispatch`.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func main() {
	name := filepath.Base(os.Args[0])
	var err error
	switch name {
	case "focus-urgent":
		err = focusUrgent()
	default: // focus-window, move-window
		err = edge(name, os.Args[1:])
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", name, err)
		os.Exit(1)
	}
}

// A window, as `mmsg get all-clients` and `mmsg get focusing-client` print
// it (only the fields used here)
type client struct {
	ID           int     `json:"id"`
	Monitor      string  `json:"monitor"`
	Tags         []int   `json:"tags"`
	IsVisible    bool    `json:"is_visible"`
	IsFocused    bool    `json:"is_focused"`
	IsFloating   bool    `json:"is_floating"`
	IsFullscreen bool    `json:"is_fullscreen"`
	IsMinimized  bool    `json:"is_minimized"`
	IsScratchpad bool    `json:"is_scratchpad"`
	IsUrgent     bool    `json:"is_urgent"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	Width        float64 `json:"width"`
}

// Whether it's among the tag's tiled windows: not floating, minimized or in
// the scratchpad
func (c client) tiled() bool {
	return !c.IsFloating && !c.IsMinimized && !c.IsScratchpad
}

type clients struct {
	Clients []client `json:"clients"`
}

// A display, as `mmsg get all-monitors` prints it
type monitor struct {
	Name   string `json:"name"`
	Active bool   `json:"active"` // the focused one
	TagNum int    `json:"tag_num"`
	Tags   []struct {
		Index       int  `json:"index"`
		IsActive    bool `json:"is_active"`
		ClientCount int  `json:"client_count"`
	} `json:"tags"`
}

// Runs `mmsg get <what>` and reads its JSON into v
func mmsgGet(what string, v any) error {
	out, err := exec.Command("mmsg", "get", what).Output()
	if err != nil {
		return fmt.Errorf("mmsg get %s: %w", what, err)
	}
	return json.Unmarshal(out, v)
}

func allClients() ([]client, error) {
	var c clients
	err := mmsgGet("all-clients", &c)
	return c.Clients, err
}

// The focused display, or false if mango says none is
func activeMonitor() (monitor, bool, error) {
	var m struct {
		Monitors []monitor `json:"monitors"`
	}
	if err := mmsgGet("all-monitors", &m); err != nil {
		return monitor{}, false, err
	}
	for _, mon := range m.Monitors {
		if mon.Active {
			return mon, true, nil
		}
	}
	return monitor{}, false, nil
}

// Runs `mmsg dispatch <args>`
func dispatch(args ...string) error {
	return exec.Command("mmsg", append([]string{"dispatch"}, args...)...).Run()
}
