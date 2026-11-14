package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// A stand-in mmsg, first in PATH. `get` and `watch` print the files written
// with setClients, setMonitors, setFocused and setWatch; `dispatch` is logged
type fake struct {
	t   *testing.T
	dir string
}

func newFake(t *testing.T) *fake {
	f := &fake{t: t, dir: t.TempDir()}
	script := `#!/bin/sh
d=` + f.dir + `
case "$1 $2" in
"get all-clients") cat $d/clients ;;
"get all-monitors") cat $d/monitors ;;
"get focusing-client") cat $d/focused 2>/dev/null || exit 1 ;;
"watch all-clients") cat $d/watch ;;
dispatch*) echo "$*" >> $d/log ;;
esac
`
	if err := os.WriteFile(filepath.Join(f.dir, "mmsg"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", f.dir+":/usr/bin")
	// Display DP-2 is focused, on tag 1 of 9, which has a window
	f.setMonitors(1, map[int]int{1: 1})
	f.setClients()
	return f
}

func (f *fake) write(name string, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.dir, name), append(data, '\n'), 0o644); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fake) setClients(all ...client) {
	if all == nil {
		all = []client{}
	}
	f.write("clients", clients{all})
}

// The focused window: written like mmsg prints it, and added to the others
func (f *fake) setFocused(c client, others ...client) {
	c.IsFocused = true
	f.write("focused", c)
	f.setClients(append([]client{c}, others...)...)
}

// DP-2, focused, showing tag active of 9, with the given window counts per
// tag; and eDP-1, not focused
func (f *fake) setMonitors(active int, counts map[int]int) {
	var tags []string
	for i := 1; i <= 9; i++ {
		tags = append(tags, fmt.Sprintf(`{"index":%d,"is_active":%t,"client_count":%d}`, i, i == active, counts[i]))
	}
	data := `{"monitors":[{"name":"eDP-1","active":false,"tag_num":9,"tags":[]},` +
		`{"name":"DP-2","active":true,"tag_num":9,"tags":[` + strings.Join(tags, ",") + `]}]}`
	os.WriteFile(filepath.Join(f.dir, "monitors"), []byte(data+"\n"), 0o644)
}

// The lines mmsg watch prints, one per state
func (f *fake) setWatch(lines ...string) {
	os.WriteFile(filepath.Join(f.dir, "watch"), []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

func (f *fake) dispatched() []string {
	data, _ := os.ReadFile(filepath.Join(f.dir, "log"))
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSpace(string(data)), "\n")
}

func (f *fake) check(want ...string) {
	f.t.Helper()
	if got := f.dispatched(); !slices.Equal(got, want) {
		f.t.Errorf("dispatched %q, want %q", got, want)
	}
}

// A tiled, visible window on DP-2's given tag, width 960
func win(id, tag int, x, y float64) client {
	return client{ID: id, Monitor: "DP-2", Tags: []int{tag}, IsVisible: tag == 1, X: x, Y: y, Width: 960}
}
