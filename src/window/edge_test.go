package main

import "testing"

// A window on that side of the focused one: focusdir, like plain mango
func TestFocusNeighbour(t *testing.T) {
	f := newFake(t)
	f.setFocused(win(1, 1, 0, 0), win(2, 1, 960, 0))
	if err := edge("focus-window", []string{"right"}); err != nil {
		t.Fatal(err)
	}
	f.check("dispatch focusdir,right")
}

// None to the right: the next tag, on its leftmost window (the top one of
// the column). Floating windows and other displays' don't count
func TestFocusNextTag(t *testing.T) {
	f := newFake(t)
	floating := win(6, 2, -100, 0)
	floating.IsFloating = true
	other := win(7, 2, -50, 0)
	other.Monitor = "eDP-1"
	f.setFocused(win(1, 1, 960, 0), win(2, 1, 0, 0),
		win(3, 2, 960, 0), win(4, 2, 0, 500), win(5, 2, 0, 0), floating, other)
	edge("focus-window", []string{"right"})
	f.check("dispatch view,2,0", "dispatch focusid client,5")
}

// None to the left: the previous tag, on its rightmost window
func TestFocusPreviousTag(t *testing.T) {
	f := newFake(t)
	f.setMonitors(2, map[int]int{1: 3, 2: 1})
	focused := win(1, 2, 0, 0)
	focused.IsVisible = true
	f.setFocused(focused, win(2, 1, 0, 0), win(3, 1, 960, 500), win(4, 1, 960, 0))
	edge("focus-window", []string{"left"})
	f.check("dispatch view,1,0", "dispatch focusid client,4")
}

// Windows that aren't tiled, or not shown, aren't neighbours, nor is one
// whose middle is level with the focused one's
func TestNotNeighbours(t *testing.T) {
	f := newFake(t)
	floating, minimized, scratchpad, hidden, otherDisplay, level :=
		win(2, 1, 960, 0), win(3, 1, 960, 0), win(4, 1, 960, 0), win(5, 1, 960, 0), win(6, 1, 960, 0), win(7, 1, 0, 500)
	floating.IsFloating = true
	minimized.IsMinimized = true
	scratchpad.IsScratchpad = true
	hidden.IsVisible = false
	otherDisplay.Monitor = "eDP-1"
	f.setFocused(win(1, 1, 0, 0), floating, minimized, scratchpad, hidden, otherDisplay, level)
	edge("focus-window", []string{"right"})
	f.check("dispatch view,2,0")
}

// The first and last tags are as far as it goes
func TestFocusStopsAtEnds(t *testing.T) {
	f := newFake(t)
	f.setFocused(win(1, 1, 0, 0))
	edge("focus-window", []string{"left"})
	f.check()

	f.setMonitors(9, map[int]int{9: 1})
	edge("focus-window", []string{"right"})
	f.check()
}

// An empty tag has no focused window: it still goes to the next tag
func TestFocusFromEmptyTag(t *testing.T) {
	f := newFake(t)
	f.setMonitors(3, nil)
	edge("focus-window", []string{"right"})
	f.check("dispatch view,4,0")
}

func TestUsage(t *testing.T) {
	newFake(t)
	for _, args := range [][]string{nil, {"up"}} {
		if err := edge("focus-window", args); err == nil || err.Error() != "usage: focus-window left|right" {
			t.Errorf("%q: %v", args, err)
		}
	}
}

func TestMoveNeighbour(t *testing.T) {
	f := newFake(t)
	f.setFocused(win(1, 1, 960, 0), win(2, 1, 0, 0))
	edge("move-window", []string{"left"})
	f.check("dispatch move_client,left")
}

// None that side: to the next tag, following it
func TestMoveToNextTag(t *testing.T) {
	f := newFake(t)
	f.setFocused(win(1, 1, 960, 0), win(2, 1, 0, 0))
	edge("move-window", []string{"right"})
	f.check("dispatch tag,2,0")
}

// A floating or fullscreen window goes to the next tag even with a
// neighbour, as it has no place among the tiled ones
func TestMoveFloating(t *testing.T) {
	for _, set := range []func(*client){
		func(c *client) { c.IsFloating = true },
		func(c *client) { c.IsFullscreen = true },
	} {
		f := newFake(t)
		focused := win(1, 1, 0, 0)
		set(&focused)
		f.setFocused(focused, win(2, 1, 960, 0))
		edge("move-window", []string{"right"})
		f.check("dispatch tag,2,0")
	}
}

func TestMoveNothing(t *testing.T) {
	// No focused window
	f := newFake(t)
	edge("move-window", []string{"right"})
	f.check()

	// The last tag
	f = newFake(t)
	f.setMonitors(9, map[int]int{9: 1})
	focused := win(1, 9, 0, 0)
	focused.IsVisible = true
	f.setFocused(focused)
	edge("move-window", []string{"right"})
	f.check()
}
