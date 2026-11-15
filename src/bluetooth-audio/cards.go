package main

// Reading `pactl list cards`. Each card looks like this (tabs for indents):
//
//	Card #61
//		Name: bluez_card.AA_BB_CC_DD_EE_FF
//		Driver: module-bluez5-device.c
//		Properties:
//			api.bluez5.address = "AA:BB:CC:DD:EE:FF"
//			...
//		Profiles:
//			off: Off (sinks: 0, sources: 0, priority: 0, available: yes)
//			a2dp-sink: High Fidelity Playback (A2DP Sink, codec AAC) (sinks: 1, sources: 0, priority: 18, available: yes)
//			...
//		Active Profile: a2dp-sink
//		Ports:
//			...

import (
	"cmp"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

type card struct {
	name, address, active string
	// The lines under Profiles:, as pactl prints them
	profiles []string
}

// Whether this is the device's card: its bluez address, or a name ending in
// the address with _ for : (bluez_card.AA_BB_CC_DD_EE_FF)
func (c card) is(address string) bool {
	address = strings.ToUpper(address)
	return c.name != "" && (strings.ToUpper(c.address) == address ||
		strings.HasSuffix(strings.ToUpper(c.name), strings.ReplaceAll(address, ":", "_")))
}

// The first card in text that is the device's
func findCard(text, address string) (card, bool) {
	var c card
	section := ""
	for _, line := range strings.Split(text, "\n") {
		switch {
		case strings.HasPrefix(line, "Card #"):
			if c.is(address) {
				return c, true
			}
			c, section = card{}, ""
		case strings.HasPrefix(line, "\tName: "):
			c.name = strings.TrimPrefix(line, "\tName: ")
		case strings.HasPrefix(line, "\tActive Profile: "):
			c.active = strings.TrimPrefix(line, "\tActive Profile: ")
			section = ""
		case strings.HasPrefix(line, "\t\t"):
			line = strings.TrimPrefix(line, "\t\t")
			switch section {
			case "Properties":
				if value, ok := strings.CutPrefix(line, `api.bluez5.address = "`); ok && strings.HasSuffix(value, `"`) {
					c.address = strings.TrimSuffix(value, `"`)
				}
			case "Profiles":
				c.profiles = append(c.profiles, line)
			}
		case strings.HasPrefix(line, "\t") && strings.HasSuffix(line, ":"):
			// The start of a section: Properties:, Profiles:, Ports:
			section = strings.TrimSuffix(strings.TrimPrefix(line, "\t"), ":")
		case strings.HasPrefix(line, "\t"):
			section = ""
		}
	}
	return c, c.is(address)
}

// "a2dp-sink: High Fidelity Playback (A2DP Sink, codec AAC) (sinks: 1, sources: 0, priority: 18, available: yes)"
var profileLine = regexp.MustCompile(`^(.*) \(sinks: [0-9]+, sources: [0-9]+, priority: ([0-9]+), available: ([a-z]+)\)$`)

// "... (A2DP Sink, codec AAC)": AAC
var codecName = regexp.MustCompile(`codec ([^)]+)\)`)

// The profiles worth picking from, high-quality audio first, then the
// higher priority first. Off and unavailable ones are left out
func choices(lines []string) []profile {
	type choice struct {
		profile
		a2dp     bool
		priority int
	}
	var list []choice
	for _, line := range lines {
		name, rest, _ := strings.Cut(line, ": ")
		m := profileLine.FindStringSubmatch(rest)
		if m == nil {
			continue
		}
		description, available := m[1], m[3]
		if name == "off" || available == "no" {
			continue
		}
		priority, _ := strconv.Atoi(m[2])

		// "High Fidelity Playback (A2DP Sink, codec AAC)": "High-quality
		// audio", "AAC"
		p := profile{Name: name}
		if c := codecName.FindStringSubmatch(description); c != nil {
			p.Codec = c[1]
		}
		switch {
		case strings.HasPrefix(name, "a2dp"):
			p.Label = "High-quality audio"
		case strings.HasPrefix(name, "headset"):
			p.Label = "Headset with mic"
		default:
			p.Label, p.Codec = cmp.Or(description, name), ""
		}
		list = append(list, choice{p, strings.HasPrefix(name, "a2dp"), priority})
	}

	slices.SortStableFunc(list, func(a, b choice) int {
		if a.a2dp != b.a2dp {
			if a.a2dp {
				return -1
			}
			return 1
		}
		return cmp.Compare(b.priority, a.priority)
	})
	profiles := []profile{} // [] in the JSON, not null
	for _, c := range list {
		profiles = append(profiles, c.profile)
	}
	return profiles
}
