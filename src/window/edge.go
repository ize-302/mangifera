package main

// focus-window left|right: moves the focus left or right: to the neighbour on
// the tag, or, when there's none on that side, to the previous or next tag,
// landing on the window at the edge it came in from.
//
// move-window left|right: swaps the focused window with its neighbour on the
// tag, or, when there's none on that side, moves it to the previous or next
// tag and follows it.
//
// Both stop at the first and last tag.

import (
	"errors"
	"slices"
	"sort"
	"strconv"
)

// What both need to know, for going dir (left or right)
type place struct {
	monitor   string
	focused   *client // the focused window, if it's on this tag
	neighbour bool    // whether a tiled window is on that side of it
	target    int     // the tag on that side, or 0 past the first or last
}

func edge(name string, args []string) error {
	if len(args) == 0 || (args[0] != "left" && args[0] != "right") {
		return errors.New("usage: " + name + " left|right")
	}
	dir := args[0]
	p, ok, err := findPlace(dir)
	if err != nil || !ok {
		return err
	}
	if name == "move-window" {
		return moveWindow(dir, p)
	}
	return focusWindow(dir, p)
}

func findPlace(dir string) (p place, ok bool, err error) {
	mon, ok, err := activeMonitor()
	if err != nil || !ok {
		return p, false, err
	}
	p.monitor = mon.Name

	// Read from the display rather than the focused window, as an empty tag
	// has none
	tag := 0
	for _, t := range mon.Tags {
		if t.IsActive {
			tag = t.Index
			break
		}
	}
	p.target = tag - 1
	if dir == "right" {
		p.target = tag + 1
	}
	if p.target < 1 || p.target > mon.TagNum {
		p.target = 0
	}

	var focused client
	if mmsgGet("focusing-client", &focused) == nil && focused.Monitor == mon.Name && focused.IsVisible {
		p.focused = &focused
	}
	if p.focused == nil {
		return p, true, nil
	}

	// Another visible tiled window on the same display whose middle is
	// further left or right than the focused one's
	all, err := allClients()
	if err != nil {
		return p, false, err
	}
	mid := focused.X + focused.Width/2
	for _, c := range all {
		if c.ID == focused.ID || c.Monitor != focused.Monitor || !c.IsVisible || !c.tiled() {
			continue
		}
		m := c.X + c.Width/2
		if (dir == "right" && m > mid) || (dir == "left" && m < mid) {
			p.neighbour = true
			break
		}
	}
	return p, true, nil
}

func focusWindow(dir string, p place) error {
	if p.neighbour {
		return dispatch("focusdir," + dir)
	}
	if p.target == 0 {
		return nil
	}
	target := strconv.Itoa(p.target)
	if err := dispatch("view," + target + ",0"); err != nil {
		return err
	}

	all, err := allClients()
	if err != nil {
		return err
	}
	if id, ok := edgeWindow(all, p.monitor, p.target, dir); ok {
		return dispatch("focusid", "client,"+strconv.Itoa(id))
	}
	return nil
}

// The tiled window on the tag at the edge it's entered from: going right,
// the leftmost (the top one of a column); going left, the rightmost
func edgeWindow(all []client, monitor string, tag int, dir string) (id int, ok bool) {
	var onTag []client
	for _, c := range all {
		if c.Monitor == monitor && slices.Contains(c.Tags, tag) && c.tiled() {
			onTag = append(onTag, c)
		}
	}
	if len(onTag) == 0 {
		return 0, false
	}
	// How far it is from that edge
	key := func(c client) float64 {
		if dir == "right" {
			return c.X
		}
		return -(c.X + c.Width)
	}
	sort.SliceStable(onTag, func(i, j int) bool {
		if key(onTag[i]) != key(onTag[j]) {
			return key(onTag[i]) < key(onTag[j])
		}
		return onTag[i].Y < onTag[j].Y
	})
	return onTag[0].ID, true
}

func moveWindow(dir string, p place) error {
	if p.focused == nil {
		return nil
	}
	// A floating or fullscreen window has no place among the tiled ones to
	// move to
	if !p.focused.IsFloating && !p.focused.IsFullscreen && p.neighbour {
		return dispatch("move_client," + dir)
	}
	if p.target == 0 {
		return nil
	}
	return dispatch("tag," + strconv.Itoa(p.target) + ",0")
}
