// screenshot: takes a screenshot of an area picked with slurp, opens it in
// satty (config/satty/config.toml) to edit and save or copy, then notifies.
// A saved one's notification has buttons to open it or show it in the file
// manager. Run by Super+S and the toolbox. Pressing it again while picking
// cancels.
//
// satty runs `screenshot --copy` to copy (see copyImage), so this run can
// tell a copy from closing satty.
//
// install.sh builds this into ~/.local/bin/screenshot (see build.sh).
package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	var err error
	if len(os.Args) > 1 && os.Args[1] == "--copy" {
		err = copyImage()
	} else {
		err = run()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "screenshot:", err)
		os.Exit(1)
	}
}

func run() error {
	// Already picking an area: this press cancels it
	if exec.Command("pkill", "-x", "slurp").Run() == nil {
		return nil
	}

	// -o also lets a click pick a whole screen. It fails on Escape
	out, err := exec.Command("slurp", "-o").Output()
	if err != nil {
		return nil
	}
	area := strings.TrimSpace(string(out))

	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	dir := filepath.Join(home, "Pictures", "Screenshots")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	started := time.Now()
	copied, err := edit(area, dir)
	if err != nil {
		return err
	}

	// satty names the file itself, so look for the one it just saved
	if saved := newestSince(dir, started); saved != "" {
		return notify(saved)
	}
	if copied {
		cmd := exec.Command("notify-send", "-a", "Screenshot",
			"Screenshot copied", "Paste it with Ctrl+V")
		return cmd.Run()
	}
	return nil // closed without saving or copying
}

// Grabs the area with grim and opens it in satty, which saves into dir.
// Says whether satty copied it
func edit(area, dir string) (copied bool, err error) {
	png, err := exec.Command("grim", "-g", area, "-").Output()
	if err != nil {
		return false, fmt.Errorf("grim: %w", err)
	}

	self, err := os.Executable()
	if err != nil {
		return false, err
	}
	// copyImage creates it. One per run, so two screenshots at once don't
	// mix up
	marker := filepath.Join(os.TempDir(), fmt.Sprintf("screenshot-%d-copied", os.Getpid()))
	defer os.Remove(marker)

	satty := exec.Command("satty", "--filename", "-",
		"--output-filename", filepath.Join(dir, "%Y-%m-%d_%H-%M-%S.png"),
		// Instead of the config's wl-copy
		"--copy-command", self+" --copy")
	// satty passes it on to the copy command
	satty.Env = append(os.Environ(), "SCREENSHOT_COPIED="+marker)
	satty.Stdin = bytes.NewReader(png)
	satty.Stderr = os.Stderr
	if err := satty.Run(); err != nil {
		return false, fmt.Errorf("satty: %w", err)
	}

	_, err = os.Stat(marker)
	return err == nil, nil
}

// Run by satty to copy, with the image on stdin: copies it with wl-copy, and
// creates the marker that tells the run that started satty a copy happened
func copyImage() error {
	wlCopy := exec.Command("wl-copy")
	wlCopy.Stdin = os.Stdin
	wlCopy.Stderr = os.Stderr
	if err := wlCopy.Run(); err != nil {
		return fmt.Errorf("wl-copy: %w", err)
	}
	marker := os.Getenv("SCREENSHOT_COPIED")
	if marker == "" {
		return nil // run by hand, not by satty
	}
	return os.WriteFile(marker, nil, 0o600)
}

// The newest file in dir changed after since, or "" if there's none
func newestSince(dir string, since time.Time) string {
	entries, _ := os.ReadDir(dir)
	newest, newestTime := "", since
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		if info.ModTime().After(newestTime) {
			newest, newestTime = filepath.Join(dir, entry.Name()), info.ModTime()
		}
	}
	return newest
}

// Notifies that saved was saved, and does what its clicked button says.
// notify-send --wait prints the button's name once one is clicked
func notify(saved string) error {
	// Gives up waiting after an hour, like the bash version
	ctx, cancel := context.WithTimeout(context.Background(), time.Hour)
	defer cancel()
	out, _ := exec.CommandContext(ctx, "notify-send", "-a", "Screenshot", "-i", saved,
		"--action=default=Open", "--action=folder=Show in folder", "--wait",
		"Screenshot saved", filepath.Base(saved)).Output()

	switch strings.TrimSpace(string(out)) {
	case "default": // the notification itself was clicked
		return exec.Command("xdg-open", saved).Run()
	case "folder":
		return exec.Command("gdbus", "call", "--session",
			"--dest", "org.freedesktop.FileManager1",
			"--object-path", "/org/freedesktop/FileManager1",
			"--method", "org.freedesktop.FileManager1.ShowItems",
			"['file://"+saved+"']", "").Run()
	}
	return nil // dismissed, or timed out
}
