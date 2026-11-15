package main

import (
	"encoding/json"
	"testing"
	"time"
)

// What the bash version printed, for times that need zero-padding and not
func TestClock(t *testing.T) {
	for _, tc := range []struct {
		now                time.Time
		hour, day, tooltip string
	}{
		{time.Date(2026, 11, 5, 6, 5, 0, 0, time.Local), "06:05", "Thu Nov 5", "Thursday, 05 November 2026"},
		{time.Date(2026, 11, 15, 23, 59, 59, 0, time.Local), "23:59", "Sun Nov 15", "Sunday, 15 November 2026"},
		{time.Date(2027, 1, 1, 0, 0, 0, 0, time.Local), "00:00", "Fri Jan 1", "Friday, 01 January 2027"},
	} {
		data, err := clock(tc.now)
		if err != nil {
			t.Fatal(err)
		}
		var got format
		if err := json.Unmarshal(data, &got); err != nil {
			t.Fatalf("%s: not JSON: %v", data, err)
		}
		wantText := "<span size='10pt' line_height='0.85' weight='600'>" + tc.hour + "</span>\n" +
			"<span size='7.5pt' alpha='80%' line_height='0.85'>" + tc.day + "</span>"
		if got.Text != wantText {
			t.Errorf("%v: text %q, want %q", tc.now, got.Text, wantText)
		}
		if got.Tooltip != tc.tooltip {
			t.Errorf("%v: tooltip %q, want %q", tc.now, got.Tooltip, tc.tooltip)
		}
	}
}

// A time zone far from UTC keeps its own date (11pm in Honolulu is the next
// day in UTC)
func TestClockTimeZone(t *testing.T) {
	honolulu := time.FixedZone("HST", -10*60*60)
	data, err := clock(time.Date(2026, 11, 15, 23, 0, 0, 0, honolulu))
	if err != nil {
		t.Fatal(err)
	}
	var got format
	json.Unmarshal(data, &got)
	if want := "Sunday, 15 November 2026"; got.Tooltip != want {
		t.Errorf("tooltip %q, want %q", got.Tooltip, want)
	}
}
