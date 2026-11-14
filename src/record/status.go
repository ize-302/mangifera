package main

// record-status: the bar's recording indicator, run by waybar for as long as
// the bar is up (config/waybar/config.jsonc). While wf-recorder runs, it
// prints the dot and how long it has been going each second, as waybar JSON;
// otherwise one empty line, then it sleeps until record-toggle wakes it
// (SIGUSR1) instead of checking every second.

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

const notRecording = `{"text": ""}`

func recordStatus() error {
	// Dies with waybar instead of sleeping on forever
	syscall.RawSyscall(syscall.SYS_PRCTL, syscall.PR_SET_PDEATHSIG, uintptr(syscall.SIGTERM), 0)

	// Before anything can wake it, so no wake-up is missed
	wake := make(chan os.Signal, 1)
	signal.Notify(wake, syscall.SIGUSR1)
	// Writing to waybar once it's gone fails (SIGPIPE) instead of killing
	// this, so the file below is still removed
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGINT, syscall.SIGPIPE)

	file, err := registerBar()
	if err != nil {
		return err
	}
	defer os.Remove(file)

	for {
		// nil waits forever: only a wake-up or quitting ends it
		var tick <-chan time.Time
		line := notRecording
		if secs, ok := recordingFor(); ok {
			line = recordingLine(secs)
			tick = time.After(time.Second)
		}
		if _, err := fmt.Println(line); err != nil {
			return nil // waybar is gone
		}

		select {
		case <-tick:
		case <-wake:
		case <-quit:
			return nil
		}
	}
}

// Leaves this one's file in barsDir, after removing those of record-status
// runs that are gone
func registerBar() (string, error) {
	dir := barsDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	entries, _ := os.ReadDir(dir)
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil || syscall.Kill(pid, 0) != nil {
			os.Remove(filepath.Join(dir, entry.Name()))
		}
	}
	file := filepath.Join(dir, strconv.Itoa(os.Getpid()))
	return file, os.WriteFile(file, nil, 0o644)
}

// The bar's text while recording. 󰑊 is the record dot's Nerd Font
// glyph, written as JSON escapes. The dot pulses (style.css); the time keeps
// its own colour so it stays put
func recordingLine(secs int) string {
	return fmt.Sprintf(`{"text": "󰑊 <span color=\"#ffffff\" font_features=\"tnum\">%s</span>", "tooltip": "Recording the screen. Click to stop", "class": "recording"}`, elapsed(secs))
}

// "04:05", or "1:02:05" from an hour
func elapsed(secs int) string {
	if secs >= 3600 {
		return fmt.Sprintf("%d:%02d:%02d", secs/3600, secs%3600/60, secs%60)
	}
	return fmt.Sprintf("%02d:%02d", secs/60, secs%60)
}
