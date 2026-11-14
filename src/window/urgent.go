package main

// focus-urgent: focuses windows that turn urgent (mango's focus_on_activate
// misses some). One in the scratchpad is moved to an empty tag.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
)

func focusUrgent() error {
	// mmsg prints every window as one line of JSON whenever any changes
	watch := exec.Command("mmsg", "watch", "all-clients")
	out, err := watch.StdoutPipe()
	if err != nil {
		return err
	}
	if err := watch.Start(); err != nil {
		return fmt.Errorf("mmsg: %w", err)
	}

	urgent := map[int]bool{} // the unfocused urgent windows, as of the last line
	lines := bufio.NewScanner(out)
	lines.Buffer(nil, 16<<20) // a line holds every window, so it can be long
	for lines.Scan() {
		var state clients
		if json.Unmarshal(lines.Bytes(), &state) != nil {
			continue
		}
		now := map[int]bool{}
		for _, c := range state.Clients {
			if c.IsUrgent && !c.IsFocused {
				now[c.ID] = true
			}
		}
		id, ok := newestNew(urgent, now)
		urgent = now
		if !ok {
			continue
		}
		if err := focus(id, state.Clients); err != nil {
			fmt.Fprintln(os.Stderr, "focus-urgent:", err) // and keep watching
		}
	}
	return watch.Wait()
}

// The newest (highest id) window in now that isn't in before
func newestNew(before, now map[int]bool) (id int, ok bool) {
	for i := range now {
		if !before[i] && (!ok || i > id) {
			id, ok = i, true
		}
	}
	return id, ok
}

// Focuses the window. One in the scratchpad (minimized) is also moved to an
// empty tag, so it isn't shown over the windows of this one
func focus(id int, all []client) error {
	client := "client," + strconv.Itoa(id)
	if err := dispatch("focusid", client); err != nil {
		return err
	}
	for _, c := range all {
		if c.ID == id && c.IsMinimized {
			tag, err := freeTag()
			if err != nil {
				return err
			}
			return dispatch("tag,"+strconv.Itoa(tag)+",0", client)
		}
	}
	return nil
}

// A tag on the focused display to put a window on: this one if it's empty,
// else the first empty one, else the last
func freeTag() (int, error) {
	mon, ok, err := activeMonitor()
	if err != nil || !ok || len(mon.Tags) == 0 {
		return 0, fmt.Errorf("no tag to move it to")
	}
	for _, t := range mon.Tags {
		if t.IsActive && t.ClientCount == 0 {
			return t.Index, nil
		}
	}
	for _, t := range mon.Tags {
		if t.ClientCount == 0 {
			return t.Index, nil
		}
	}
	return mon.Tags[len(mon.Tags)-1].Index, nil
}
