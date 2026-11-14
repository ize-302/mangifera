package main

// laptop-screen on|off|lid: turns the laptop's own screen on or off. "lid"
// turns it off if the lid is closed, and does nothing otherwise.

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// The lid's state file(s), "state:      open" or "closed". The tests move it
var lidStates = "/proc/acpi/button/lid/*/state"

func laptopScreen(args []string) error {
	arg := ""
	if len(args) > 0 {
		arg = args[0]
	}
	var flag string
	switch arg {
	case "on":
		flag = "--on"
	case "off":
		flag = "--off"
	case "lid":
		if !lidClosed() {
			return nil
		}
		flag = "--off"
	default:
		return errors.New("usage: laptop-screen on|off|lid")
	}

	out, err := exec.Command("wlr-randr", "--json").Output()
	if err != nil {
		return fmt.Errorf("wlr-randr: %w", err)
	}
	var displays []struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(out, &displays); err != nil {
		return fmt.Errorf("wlr-randr: %w", err)
	}

	var errs []error
	for _, display := range displays {
		if !isInternal(display.Name) {
			continue
		}
		cmd := exec.Command("wlr-randr", "--output", display.Name, flag)
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", display.Name, err))
		}
	}
	return errors.Join(errs...)
}

func lidClosed() bool {
	files, _ := filepath.Glob(lidStates)
	for _, file := range files {
		if data, err := os.ReadFile(file); err == nil && strings.Contains(string(data), "closed") {
			return true
		}
	}
	return false
}
