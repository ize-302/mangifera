// bluetooth-audio: a Bluetooth device's audio profiles, through pactl.
// Quickshell can't see card profiles, so the control panel's device page
// (config/quickshell/launcher/controlpanel/ControlPanel.qml) runs this.
//
//	bluetooth-audio show ADDRESS            {"card", "active", "profiles": [...]}, or {}
//	bluetooth-audio set ADDRESS PROFILE
//
// Reading pactl's output is in cards.go.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
)

func main() {
	var err error
	switch {
	case len(os.Args) == 3 && os.Args[1] == "show":
		err = show(os.Stdout, os.Args[2])
	case len(os.Args) == 4 && os.Args[1] == "set":
		err = setProfile(os.Args[2], os.Args[3])
	default:
		err = errors.New("usage: bluetooth-audio show <address> | set <address> <profile>")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "bluetooth-audio:", err)
		os.Exit(1)
	}
}

// What show prints: the panel lists the profiles, and ticks the active one
type audio struct {
	Card     string    `json:"card"`
	Active   string    `json:"active"`
	Profiles []profile `json:"profiles"`
}

type profile struct {
	Name  string `json:"name"`
	Label string `json:"label"`
	Codec string `json:"codec"`
}

// Prints the device's card and profiles, or {} when it has no audio (or
// pactl fails, so the panel shows nothing instead of stale profiles)
func show(w io.Writer, address string) error {
	text, err := listCards()
	c, found := findCard(text, address)
	if err != nil || !found {
		fmt.Fprintln(w, "{}")
		return err
	}
	out, err := json.Marshal(audio{Card: c.name, Active: c.active, Profiles: choices(c.profiles)})
	if err != nil {
		return err
	}
	fmt.Fprintln(w, string(out))
	return nil
}

func setProfile(address, name string) error {
	text, err := listCards()
	if err != nil {
		return err
	}
	c, found := findCard(text, address)
	if !found {
		return fmt.Errorf("no audio for %s", address)
	}
	cmd := pactl("set-card-profile", c.name, name)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("pactl: %w", err)
	}
	return nil
}

// `pactl list cards`, whose text the codec names are read from
func listCards() (string, error) {
	out, err := pactl("list", "cards").Output()
	if err != nil {
		return "", fmt.Errorf("pactl: %w", err)
	}
	return string(out), nil
}

// pactl, in English
func pactl(args ...string) *exec.Cmd {
	cmd := exec.Command("pactl", args...)
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	return cmd
}
