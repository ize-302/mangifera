// wallpaper [--random|--follow|FILE]: sets the wallpaper with awww.
//
//	wallpaper           the last one again (at login), or a random one
//	wallpaper --random  a different random one from ~/Pictures/wallpapers
//	wallpaper FILE      that image
//	wallpaper --follow  keeps running, and sets it again on each display
//	                    that turns on
//
// It saves the image's path (for next time and the lock screen), a small copy
// for the lock screen, and a copy in /var/lib/sddm-wallpaper for the login
// screen. mango runs it at login, and once more with --follow
// (config/mango/config.conf); Super+Shift+W and the toolbox run --random.
//
// install.sh builds this into ~/.local/bin/wallpaper (see build.sh).
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Where things are. Package variables so the tests can move them
var (
	// Copied here for SDDM, which can't read $HOME
	sddmDir = "/var/lib/sddm-wallpaper"
	// How long to wait for awww to be ready, and for it to see a display
	waitTries = 50
	waitStep  = 100 * time.Millisecond
)

type paths struct {
	wallpapers string // ~/Pictures/wallpapers, where --random picks from
	fallback   string // shown when there's nothing else
	state      string // the current wallpaper's path
	lockScreen string // the small copy for the lock screen
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "wallpaper:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	p, err := findPaths()
	if err != nil {
		return err
	}
	arg := ""
	if len(args) > 0 {
		arg = args[0]
	}
	if arg == "--follow" {
		return follow(p)
	}
	return set(p, arg)
}

func findPaths() (paths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return paths{}, err
	}
	stateDir := os.Getenv("XDG_STATE_HOME")
	if stateDir == "" {
		stateDir = filepath.Join(home, ".local", "state")
	}
	stateDir = filepath.Join(stateDir, "mangifera")
	return paths{
		wallpapers: filepath.Join(home, "Pictures", "wallpapers"),
		fallback:   filepath.Join(home, ".local", "share", "mangifera", "default-wallpaper.jpg"),
		state:      filepath.Join(stateDir, "wallpaper"),
		lockScreen: filepath.Join(stateDir, "lock-wallpaper.jpg"),
	}, nil
}

// Sets the wallpaper: arg is "", "--random" or an image's path
func set(p paths, arg string) error {
	current := readCurrent(p)

	var img string
	switch arg {
	case "--random":
		img = pickRandomWallpaper(p.wallpapers, current)
		if img == "" {
			img = current // the only one there
		}
	case "":
		img = current
		if !isFile(img) {
			img = pickRandomWallpaper(p.wallpapers, current)
		}
	default:
		abs, err := filepath.Abs(arg)
		if err != nil {
			return err
		}
		// Like realpath: the real file, and an error if there's none
		if img, err = filepath.EvalSymlinks(abs); err != nil {
			return err
		}
	}
	if !isFile(img) {
		img = p.fallback
	}

	if err := startAwww(); err != nil {
		return err
	}

	// Fades into a new image; the same one again (at login) shows at once
	transition := []string{"--transition-type", "none"}
	if img != current {
		transition = []string{"--transition-type", "fade", "--transition-duration", "1", "--transition-fps", "60"}
	}
	awwwImg := exec.Command("awww", slices.Concat([]string{"img"}, transition, []string{"--", img})...)
	awwwImg.Stderr = os.Stderr
	if err := awwwImg.Run(); err != nil {
		return fmt.Errorf("awww img: %w", err)
	}

	// swaybg drew the wallpaper before awww
	exec.Command("pkill", "-u", strconv.Itoa(os.Getuid()), "-x", "swaybg").Run()

	if err := os.MkdirAll(filepath.Dir(p.state), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(p.state, []byte(img+"\n"), 0o644); err != nil {
		return err
	}

	// Each one runs even if the other fails, like in the bash version
	return errors.Join(
		saveLockScreen(p, img, img != current),
		saveForSDDM(img, img != current),
	)
}

// The wallpaper set last time, or "" if there's none
func readCurrent(p paths) string {
	data, _ := os.ReadFile(p.state)
	return strings.TrimRight(string(data), "\n")
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// A random .jpg, .jpeg or .png under dir (in subfolders too, following links)
// other than current, or "" if there's none
func pickRandomWallpaper(dir, current string) string {
	var images []string
	seen := map[string]bool{} // folders already looked in, against link loops
	var walk func(dir string)
	walk = func(dir string) {
		real, err := filepath.EvalSymlinks(dir)
		if err != nil || seen[real] {
			return
		}
		seen[real] = true

		entries, _ := os.ReadDir(dir)
		for _, entry := range entries {
			path := filepath.Join(dir, entry.Name())
			info, err := os.Stat(path) // follows links
			switch {
			case err != nil:
			case info.IsDir():
				walk(path)
			case info.Mode().IsRegular() && isImage(path) && path != current:
				images = append(images, path)
			}
		}
	}
	walk(dir)

	if len(images) == 0 {
		return ""
	}
	return images[rand.IntN(len(images))]
}

func isImage(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".jpg", ".jpeg", ".png":
		return true
	}
	return false
}

// Starts awww-daemon if it isn't running, and waits until it answers
func startAwww() error {
	if awwwRunning() {
		return nil
	}
	// --no-cache: this program picks the image, not awww's own last-used
	// cache. Its own session, like setsid -f, so it outlives this program
	daemon := exec.Command("awww-daemon", "--quiet", "--no-cache")
	daemon.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := daemon.Start(); err != nil {
		return fmt.Errorf("awww-daemon: %w", err)
	}
	daemon.Process.Release()

	for range waitTries {
		if awwwRunning() {
			break
		}
		time.Sleep(waitStep)
	}
	return nil
}

func awwwRunning() bool {
	return exec.Command("awww", "query").Run() == nil
}

// The lock screen shows the wallpaper blurred at a quarter size. A full-size
// photo takes a second to decode, which it would show as a blank screen, so
// it gets a small copy. Made again only for a new wallpaper, or if it's gone
func saveLockScreen(p paths, img string, changed bool) error {
	if _, err := os.Stat(p.lockScreen); err == nil && !changed {
		return nil
	}
	tmp := p.lockScreen + ".tmp.jpg"
	magick := exec.Command("magick", "-define", "jpeg:size=2560x1440", img,
		"-auto-orient", "-thumbnail", "1280x720^", "-quality", "90", tmp)
	magick.Stderr = os.Stderr
	if err := magick.Run(); err != nil {
		return fmt.Errorf("magick: %w", err)
	}
	return os.Rename(tmp, p.lockScreen)
}

// Copies the wallpaper for the login screen, if the folder is there and
// writable (install.sh makes it). Renamed into place, so the login screen
// never reads half an image
func saveForSDDM(img string, changed bool) error {
	current := filepath.Join(sddmDir, "current")
	if syscall.Access(sddmDir, 2 /* writable */) != nil {
		return nil
	}
	if _, err := os.Stat(current); err == nil && !changed {
		return nil
	}
	tmp := filepath.Join(sddmDir, ".current.tmp")
	if err := copyFile(img, tmp); err != nil {
		return err
	}
	return os.Rename(tmp, current)
}

func copyFile(from, to string) error {
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(to)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// --follow. awww-daemon runs with --no-cache, so it leaves a display that
// turns on (one plugged in, or the laptop's after an unplug) black. This sets
// the wallpaper again whenever one does
func follow(p paths) error {
	// Only as a signal: mango prints an event when a display turns on or off
	watch := exec.Command("mmsg", "watch", "all-monitors")
	events, err := watch.StdoutPipe()
	if err != nil {
		return err
	}
	if err := watch.Start(); err != nil {
		return fmt.Errorf("mmsg: %w", err)
	}

	known := enabledDisplays()
	lines := bufio.NewScanner(events)
	for lines.Scan() {
		now := enabledDisplays()
		added := newIn(known, now)
		known = now
		if len(added) == 0 {
			continue
		}
		// awww sees a display a moment after mango does
		for range waitTries {
			if awwwShows(added) {
				break
			}
			time.Sleep(waitStep)
		}
		if err := set(p, ""); err != nil {
			fmt.Fprintln(os.Stderr, "wallpaper:", err) // and keep following
		}
	}
	return watch.Wait()
}

// The names of the displays that are on. mango lists a display even while
// it's off, so this asks wlr-randr
func enabledDisplays() []string {
	out, err := exec.Command("wlr-randr", "--json").Output()
	if err != nil {
		return nil
	}
	return parseDisplays(out)
}

func parseDisplays(wlrRandrJSON []byte) []string {
	var displays []struct {
		Name    string `json:"name"`
		Enabled bool   `json:"enabled"`
	}
	json.Unmarshal(wlrRandrJSON, &displays)
	var names []string
	for _, display := range displays {
		if display.Enabled {
			names = append(names, display.Name)
		}
	}
	return names
}

// The names in now that aren't in before
func newIn(before, now []string) []string {
	var added []string
	for _, name := range now {
		if !slices.Contains(before, name) {
			added = append(added, name)
		}
	}
	return added
}

// Whether awww lists every one of the displays. `awww query` prints a line
// per display, like ": DP-2: 1920x1080, scale: 1, currently displaying: ..."
func awwwShows(displays []string) bool {
	out, err := exec.Command("awww", "query").Output()
	if err != nil {
		return false
	}
	return listsAll(string(out), displays)
}

func listsAll(query string, displays []string) bool {
	for _, name := range displays {
		if !strings.Contains(query, ": "+name+":") {
			return false
		}
	}
	return true
}
