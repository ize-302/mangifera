package main

import (
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// A fake home, SDDM folder and PATH, with stand-ins that log "name args".
// awww answers `query` once awww-daemon has run (or from the start, if
// running), and `img` with exit code imgCode. magick writes its last argument.
type fakes struct {
	t       *testing.T
	home    string
	bin     string
	p       paths
	sddm    string
	logFile string
}

func setup(t *testing.T, running bool, imgCode string) *fakes {
	f := &fakes{t: t, home: t.TempDir(), bin: t.TempDir(), sddm: t.TempDir()}
	f.logFile = filepath.Join(f.bin, "log")
	t.Setenv("HOME", f.home)
	t.Setenv("XDG_STATE_HOME", "")
	t.Setenv("PATH", f.bin+":/usr/bin")
	oldSDDM, oldTries := sddmDir, waitTries
	sddmDir, waitTries = f.sddm, 3
	t.Cleanup(func() { sddmDir, waitTries = oldSDDM, oldTries })

	up := filepath.Join(f.bin, "awww-up")
	if running {
		os.WriteFile(up, nil, 0o644)
	}
	f.script("awww", `case $1 in
query) [ -e `+up+` ] || exit 1; cat `+f.bin+`/query 2>/dev/null; exit 0 ;;
img) exit `+imgCode+` ;;
esac`)
	f.script("awww-daemon", "touch "+up)
	f.script("pkill", "exit 1")
	f.script("magick", `for arg; do last=$arg; done; echo small > "$last"`)

	var err error
	if f.p, err = findPaths(); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *fakes) script(name, body string) {
	script := "#!/bin/sh\necho \"" + name + " $*\" >> " + f.logFile + "\n" + body + "\n"
	if err := os.WriteFile(filepath.Join(f.bin, name), []byte(script), 0o755); err != nil {
		f.t.Fatal(err)
	}
}

// Writes a file (and its folders) under home
func (f *fakes) file(rel, content string) string {
	path := filepath.Join(f.home, rel)
	os.MkdirAll(filepath.Dir(path), 0o755)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		f.t.Fatal(err)
	}
	return path
}

func (f *fakes) log() []string {
	data, _ := os.ReadFile(f.logFile)
	return strings.Split(strings.TrimSpace(string(data)), "\n")
}

// The awww img line in the log, or ""
func (f *fakes) awwwImg() string {
	for _, line := range f.log() {
		if strings.HasPrefix(line, "awww img ") {
			return line
		}
	}
	return ""
}

func read(path string) string {
	data, _ := os.ReadFile(path)
	return string(data)
}

const fade = "--transition-type fade --transition-duration 1 --transition-fps 60"

// At login: the same wallpaper again, shown at once. The lock screen's copy
// is already there, so only SDDM's (missing) is made
func TestLogin(t *testing.T) {
	f := setup(t, true, "0")
	img := f.file("Pictures/wallpapers/a.jpg", "A")
	f.file(".local/state/mangifera/wallpaper", img+"\n")
	f.file(".local/state/mangifera/lock-wallpaper.jpg", "old small")

	if err := run(nil); err != nil {
		t.Fatal(err)
	}
	if got, want := f.awwwImg(), "awww img --transition-type none -- "+img; got != want {
		t.Errorf("ran %q, want %q", got, want)
	}
	if got := read(f.p.lockScreen); got != "old small" {
		t.Errorf("lock screen copy remade: %q", got)
	}
	if got := read(filepath.Join(f.sddm, "current")); got != "A" {
		t.Errorf("SDDM copy is %q, want the wallpaper", got)
	}
	if slices.Contains(f.log(), "awww-daemon --quiet --no-cache") {
		t.Error("started awww-daemon while it was running")
	}
	if !slices.Contains(f.log(), "pkill -u "+strconv.Itoa(os.Getuid())+" -x swaybg") {
		t.Error("swaybg wasn't stopped")
	}
}

// --random picks another image: in a subfolder or through a link, any case
// of .jpg, .jpeg or .png, never the current one or another kind of file
func TestRandom(t *testing.T) {
	f := setup(t, true, "0")
	current := f.file("Pictures/wallpapers/current.jpg", "")
	f.file("Pictures/wallpapers/notes.txt", "")
	f.file(".local/state/mangifera/wallpaper", current+"\n")
	others := []string{
		f.file("Pictures/wallpapers/b.PNG", ""),
		f.file("Pictures/wallpapers/sub/c.jpeg", ""),
	}
	elsewhere := f.file("elsewhere/d.jpg", "")
	os.Symlink(filepath.Dir(elsewhere), filepath.Join(f.home, "Pictures/wallpapers/linked"))
	others = append(others, filepath.Join(f.home, "Pictures/wallpapers/linked/d.jpg"))

	seen := map[string]bool{}
	for range 60 {
		img := pickRandomWallpaper(f.p.wallpapers, current)
		if !slices.Contains(others, img) {
			t.Fatalf("picked %q", img)
		}
		seen[img] = true
	}
	if len(seen) != len(others) {
		t.Errorf("only ever picked %v", seen)
	}

	if err := run([]string{"--random"}); err != nil {
		t.Fatal(err)
	}
	if got := f.awwwImg(); !strings.HasPrefix(got, "awww img "+fade+" -- ") {
		t.Errorf("ran %q, want a fade", got)
	}
	// A new wallpaper: saved, with new copies for the lock screen and SDDM
	saved := strings.TrimSpace(read(f.p.state))
	if !slices.Contains(others, saved) {
		t.Errorf("saved %q", saved)
	}
	if read(f.p.lockScreen) != "small\n" {
		t.Error("lock screen copy not made")
	}
	if _, err := os.Stat(filepath.Join(f.sddm, "current")); err != nil {
		t.Error("SDDM copy not made")
	}
}

// --random with only the current one: shows it again
func TestRandomOnlyOne(t *testing.T) {
	f := setup(t, true, "0")
	img := f.file("Pictures/wallpapers/a.jpg", "")
	f.file(".local/state/mangifera/wallpaper", img+"\n")
	run([]string{"--random"})
	if got, want := f.awwwImg(), "awww img --transition-type none -- "+img; got != want {
		t.Errorf("ran %q, want %q", got, want)
	}
}

// The first login: nothing saved yet, so a random one
func TestFirstLogin(t *testing.T) {
	f := setup(t, true, "0")
	img := f.file("Pictures/wallpapers/a.jpg", "")
	run(nil)
	if got, want := f.awwwImg(), "awww img "+fade+" -- "+img; got != want {
		t.Errorf("ran %q, want %q", got, want)
	}
}

// No wallpapers at all: mangifera's own
func TestFallback(t *testing.T) {
	f := setup(t, true, "0")
	run(nil)
	if got, want := f.awwwImg(), "awww img "+fade+" -- "+f.p.fallback; got != want {
		t.Errorf("ran %q, want %q", got, want)
	}
}

// A file given by a relative path is saved as its real path
func TestFile(t *testing.T) {
	f := setup(t, true, "0")
	img := f.file("photos/x.jpg", "")
	os.Symlink(img, filepath.Join(f.home, "link.jpg"))
	// Back afterwards, as the other tests run in the same folder
	wd, _ := os.Getwd()
	os.Chdir(f.home)
	defer os.Chdir(wd)
	if err := run([]string{"link.jpg"}); err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(read(f.p.state)); got != img {
		t.Errorf("saved %q, want %q", got, img)
	}
}

func TestMissingFile(t *testing.T) {
	f := setup(t, true, "0")
	if err := run([]string{"/nowhere.jpg"}); err == nil {
		t.Error("no error")
	}
	if f.awwwImg() != "" {
		t.Error("awww ran")
	}
}

// awww isn't running: the daemon is started and waited for
func TestStartsDaemon(t *testing.T) {
	f := setup(t, false, "0")
	run(nil)
	log := f.log()
	daemon := slices.Index(log, "awww-daemon --quiet --no-cache")
	img := slices.IndexFunc(log, func(line string) bool { return strings.HasPrefix(line, "awww img ") })
	if daemon < 0 || img < daemon {
		t.Errorf("ran %q, want awww-daemon then awww img", log)
	}
}

// awww img failed: nothing saved, so the next run tries the same again
func TestAwwwFails(t *testing.T) {
	f := setup(t, true, "1")
	f.file("Pictures/wallpapers/a.jpg", "")
	if err := run(nil); err == nil {
		t.Error("no error")
	}
	if _, err := os.Stat(f.p.state); err == nil {
		t.Error("saved anyway")
	}
}

// --follow: a display turning on sets the wallpaper again once awww lists
// it; one turning off, or an event with no change, doesn't
func TestFollow(t *testing.T) {
	f := setup(t, true, "0")
	img := f.file("Pictures/wallpapers/a.jpg", "")
	f.file(".local/state/mangifera/wallpaper", img+"\n")
	os.WriteFile(filepath.Join(f.bin, "query"), []byte(": DP-2: 1920x1080\n: eDP-1: 1920x1200\n"), 0o644)

	// wlr-randr answers with the next line of displays each time: at the
	// start, then after each of mango's three events
	displays := []string{
		`[{"name": "eDP-1", "enabled": true}, {"name": "DP-2", "enabled": false}]`,
		`[{"name": "eDP-1", "enabled": true}, {"name": "DP-2", "enabled": false}]`,
		`[{"name": "eDP-1", "enabled": true}, {"name": "DP-2", "enabled": true}]`,
		`[{"name": "eDP-1", "enabled": false}, {"name": "DP-2", "enabled": true}]`,
	}
	os.WriteFile(filepath.Join(f.bin, "displays"), []byte(strings.Join(displays, "\n")+"\n"), 0o644)
	f.script("wlr-randr", `n=$(cat `+f.bin+`/n 2>/dev/null || echo 1)
sed -n "${n}p" `+f.bin+`/displays
echo $((n + 1)) > `+f.bin+`/n`)
	f.script("mmsg", "echo event; echo event; echo event")

	if err := run([]string{"--follow"}); err != nil {
		t.Fatal(err)
	}
	var sets int
	for _, line := range f.log() {
		if strings.HasPrefix(line, "awww img ") {
			sets++
		}
	}
	if sets != 1 {
		t.Errorf("set the wallpaper %d times, want once:\n%s", sets, strings.Join(f.log(), "\n"))
	}
}

func TestParseDisplays(t *testing.T) {
	got := parseDisplays([]byte(`[{"name": "DP-2", "enabled": true, "modes": []}, {"name": "eDP-1", "enabled": false}]`))
	if !slices.Equal(got, []string{"DP-2"}) {
		t.Errorf("got %v", got)
	}
}

func TestListsAll(t *testing.T) {
	query := ": DP-2: 1920x1080, scale: 1, currently displaying: image: /a.jpg\n"
	if !listsAll(query, []string{"DP-2"}) {
		t.Error("DP-2 not found")
	}
	// Not just part of another name
	if listsAll(query, []string{"DP-2", "DP-1"}) || listsAll(query, []string{"P-2"}) {
		t.Error("found a display awww doesn't list")
	}
}
