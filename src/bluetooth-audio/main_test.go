package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// testdata/cards.txt is `pactl list cards` with the laptop's own sound card
// (trimmed) and two Bluetooth ones: earbuds, found by their
// api.bluez5.address, and a speaker without one, found by its card's name

// A stand-in for pactl, first in PATH: `list cards` prints the file, and
// other calls are logged. Returns the log's path
func fakePactl(t *testing.T, cards string) string {
	dir := t.TempDir()
	log := filepath.Join(dir, "log")
	script := `#!/bin/sh
[ "$LC_ALL" = C ] || echo "LC_ALL=$LC_ALL" >> ` + log + `
case "$1" in
list) cat ` + cards + ` ;;
*) echo "pactl $*" >> ` + log + ` ;;
esac
`
	if err := os.WriteFile(filepath.Join(dir, "pactl"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+":/usr/bin")
	return log
}

func readLog(t *testing.T, log string) []string {
	data, _ := os.ReadFile(log)
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSpace(string(data)), "\n")
}

func runShow(t *testing.T, address string) (audio, string) {
	t.Helper()
	var out bytes.Buffer
	if err := show(&out, address); err != nil {
		t.Fatal(err)
	}
	var got audio
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("%s: not JSON: %v", out.String(), err)
	}
	return got, out.String()
}

func TestShowEarbuds(t *testing.T) {
	log := fakePactl(t, "testdata/cards.txt")
	// Any case
	got, _ := runShow(t, "aa:bb:cc:dd:ee:ff")
	if got.Card != "bluez_card.AA_BB_CC_DD_EE_FF" || got.Active != "a2dp-sink" {
		t.Errorf("card %q, active %q", got.Card, got.Active)
	}
	// High-quality audio first, then by priority. Off and the unavailable
	// aptX are left out
	want := []profile{
		{"a2dp-sink", "High-quality audio", "AAC"},
		{"a2dp-sink-sbc", "High-quality audio", "SBC"},
		{"headset-head-unit", "Headset with mic", "mSBC"},
		{"headset-audio-gateway", "Headset with mic", ""},
		{"headset-head-unit-cvsd", "Headset with mic", "CVSD"},
	}
	if !slices.Equal(got.Profiles, want) {
		t.Errorf("profiles\n%v, want\n%v", got.Profiles, want)
	}
	if calls := readLog(t, log); calls != nil {
		t.Errorf("ran %q", calls)
	}
}

// No api.bluez5.address: found by the card's name
func TestShowByName(t *testing.T) {
	fakePactl(t, "testdata/cards.txt")
	got, _ := runShow(t, "11:22:33:44:55:66")
	want := []profile{{"a2dp-sink", "High-quality audio", "SBC"}}
	if got.Card != "bluez_card.11_22_33_44_55_66" || got.Active != "off" || !slices.Equal(got.Profiles, want) {
		t.Errorf("got %+v", got)
	}
}

// Another kind of profile keeps pactl's description, without a codec
func TestShowOtherProfiles(t *testing.T) {
	fakePactl(t, "testdata/cards.txt")
	got, _ := runShow(t, "dsp_generic")
	want := []profile{
		{"HiFi (HDMI1, HDMI2, HDMI3, Headphones, Mic1, Mic2)", "Play HiFi quality Music (HDMI1, HDMI2, HDMI3, Headphones, Mic1, Mic2)", ""},
		{"HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)", "Play HiFi quality Music (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)", ""},
		{"pro-audio", "Pro Audio", ""},
	}
	if !slices.Equal(got.Profiles, want) {
		t.Errorf("profiles\n%v, want\n%v", got.Profiles, want)
	}
}

// A device without audio (a mouse): {}
func TestShowNoAudio(t *testing.T) {
	fakePactl(t, "testdata/cards.txt")
	if _, out := runShow(t, "DF:24:0E:BB:F9:AE"); out != "{}\n" {
		t.Errorf("printed %q", out)
	}
}

// A card with no profiles to pick: [] for the panel, not null
func TestShowNoProfiles(t *testing.T) {
	cards := filepath.Join(t.TempDir(), "cards")
	os.WriteFile(cards, []byte("Card #1\n\tName: bluez_card.AA_BB_CC_DD_EE_FF\n\tProfiles:\n\t\toff: Off (sinks: 0, sources: 0, priority: 0, available: yes)\n\tActive Profile: off\n"), 0o644)
	fakePactl(t, cards)
	if _, out := runShow(t, "AA:BB:CC:DD:EE:FF"); !strings.Contains(out, `"profiles":[]`) {
		t.Errorf("printed %q", out)
	}
}

// pactl failing: {} too, so the panel drops the old profiles, and an error
func TestShowPactlFails(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	var out bytes.Buffer
	if err := show(&out, "AA:BB:CC:DD:EE:FF"); err == nil || out.String() != "{}\n" {
		t.Errorf("printed %q, error %v", out.String(), err)
	}
}

func TestSet(t *testing.T) {
	log := fakePactl(t, "testdata/cards.txt")
	if err := setProfile("aa:bb:cc:dd:ee:ff", "headset-head-unit"); err != nil {
		t.Fatal(err)
	}
	want := []string{"pactl set-card-profile bluez_card.AA_BB_CC_DD_EE_FF headset-head-unit"}
	if got := readLog(t, log); !slices.Equal(got, want) {
		t.Errorf("ran %q, want %q", got, want)
	}

	if err := setProfile("00:11:22:33:44:55", "a2dp-sink"); err == nil || err.Error() != "no audio for 00:11:22:33:44:55" {
		t.Errorf("error %v", err)
	}
	if got := readLog(t, log); !slices.Equal(got, want) {
		t.Errorf("ran %q, want %q", got, want)
	}
}
