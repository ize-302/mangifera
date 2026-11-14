package main

import (
	"reflect"
	"testing"
)

func TestFields(t *testing.T) {
	tests := []struct {
		line string
		min  int
		want []string
	}{
		{`wlan0:wifi`, 2, []string{"wlan0", "wifi"}},
		{`*:My\:Net:56`, 3, []string{"*", "My:Net", "56"}},
		{`a\\:b`, 2, []string{`a\`, "b"}},
		{`a\\\:b`, 1, []string{`a\:b`}},
		{`a\nb`, 1, []string{`a\nb`}}, // other escapes stay as they are
		{`only`, 3, []string{"only", "", ""}},
		{``, 2, []string{"", ""}},
	}
	for _, test := range tests {
		got := fields(test.line, test.min)
		if !reflect.DeepEqual(got, test.want) {
			t.Errorf("fields(%q, %d) = %q, want %q", test.line, test.min, got, test.want)
		}
	}
}

func TestBetter(t *testing.T) {
	inUse := accessPoint{inUse: true, signal: 20}
	strong := accessPoint{signal: 90}
	weak := accessPoint{signal: 10}
	if !better(inUse, strong) {
		t.Error("the access point in use should beat a stronger one")
	}
	if !better(strong, weak) {
		t.Error("the stronger access point should win")
	}
	if better(weak, strong) {
		t.Error("the weaker access point shouldn't win")
	}
}
