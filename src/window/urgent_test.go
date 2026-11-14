package main

import (
	"encoding/json"
	"testing"
)

// One `mmsg watch all-clients` line
func state(t *testing.T, all ...client) string {
	if all == nil {
		all = []client{}
	}
	data, err := json.Marshal(clients{all})
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func urgentWin(id int) client {
	c := win(id, 2, 0, 0)
	c.IsUrgent = true
	return c
}

func TestFocusUrgent(t *testing.T) {
	f := newFake(t)
	// Tag 1 (shown) has windows, 2 too, 3 is the first empty one
	f.setMonitors(1, map[int]int{1: 1, 2: 1})
	minimized := urgentWin(9)
	minimized.IsMinimized = true
	focused := urgentWin(10)
	focused.IsFocused = true
	f.setWatch(
		state(t, win(1, 1, 0, 0)),
		// Turns urgent: focused
		state(t, win(1, 1, 0, 0), urgentWin(5)),
		// Still urgent: nothing new
		state(t, win(1, 1, 0, 0), urgentWin(5)),
		// Two more at once: the newest
		state(t, urgentWin(5), urgentWin(7), urgentWin(6)),
		// One in the scratchpad: focused and moved to the empty tag
		state(t, minimized),
		// Not JSON: skipped
		"oops",
		// Urgent but already focused
		state(t, focused),
	)
	if err := focusUrgent(); err != nil {
		t.Fatal(err)
	}
	f.check(
		"dispatch focusid client,5",
		"dispatch focusid client,7",
		"dispatch focusid client,9",
		"dispatch tag,3,0 client,9",
	)
}

// This tag if it's empty, else the first empty one, else the last
func TestFreeTag(t *testing.T) {
	tests := []struct {
		active int
		counts map[int]int
		want   int
	}{
		{4, map[int]int{1: 1}, 4},
		{1, map[int]int{1: 1, 2: 1}, 3},
		{1, map[int]int{1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1}, 9},
	}
	for _, test := range tests {
		f := newFake(t)
		f.setMonitors(test.active, test.counts)
		if got, err := freeTag(); err != nil || got != test.want {
			t.Errorf("on tag %d with %v: got %d, %v; want %d", test.active, test.counts, got, err, test.want)
		}
	}
}
