package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A grab of the bar, w by h, dark grey, with these columns inked: white
// from a fifth of the way down to four fifths
func grab(w, h int, inked ...[2]int) []byte {
	pixels := make([]byte, w*h*3)
	for i := range pixels {
		pixels[i] = 30
	}
	for _, span := range inked {
		for px := span[0]; px <= span[1]; px++ {
			for py := h / 5; py < h-h/5; py++ {
				i := (py*w + px) * 3
				pixels[i], pixels[i+1], pixels[i+2] = 250, 250, 250
			}
		}
	}
	return append([]byte(fmt.Sprintf("P6\n%d %d\n255\n", w, h)), pixels...)
}

func TestAnchor(t *testing.T) {
	// Grabbed from left = 100, so columns are x - 100
	img := grab(96, 38,
		[2]int{10, 19},                 // a module, centre 14.5
		[2]int{40, 45}, [2]int{56, 60}, // an icon and its text 11 apart: one, 40-60
		[2]int{90, 95}, // another
	)
	for _, tc := range []struct{ x, want int }{
		{115, 114},   // inside: 100 + 14.5, to even
		{100, 114},   // 10 before it
		{140, 150},   // the icon and text joined: 100 + 50
		{160, 150},   // the text's end
		{170, 150},   // 10 after it, nearer than the next
		{185, 192},   // 5 before the last: 100 + 92.5, to even
		{125, 114},   // 6 after the first, 15 before the second
		{1000, 1000}, // nothing within reach: x
	} {
		if got := anchor(img, tc.x, 100); got != tc.want {
			t.Errorf("anchor at %d = %d, want %d", tc.x, got, tc.want)
		}
	}
}

// Farther than nearest (24) from every module: x
func TestAnchorTooFar(t *testing.T) {
	img := grab(96, 38, [2]int{0, 3})
	if got := anchor(img, 128, 100); got != 128 {
		t.Errorf("got %d", got)
	}
	if got := anchor(img, 127, 100); got != 102 {
		t.Errorf("24 away: got %d, want 102", got)
	}
}

// A blank bar, and ink only in the top fifth: x
func TestAnchorNoInk(t *testing.T) {
	if got := anchor(grab(96, 38), 150, 100); got != 150 {
		t.Errorf("blank: got %d", got)
	}
	img := grab(96, 38)
	header := len(img) - 96*38*3
	for px := range 96 {
		img[header+px*3] = 255 // row 0
	}
	if got := anchor(img, 150, 100); got != 150 {
		t.Errorf("top row: got %d", got)
	}
}

func TestReadPPM(t *testing.T) {
	pixels := strings.Repeat("\x01\x02\x03", 6)
	for header, ok := range map[string]bool{
		"P6\n3 2\n255\n":                  true,
		"P6 3 2 255 ":                     true,
		"P6\n# grim\n3 2\n# depth\n255\n": true,
		"P5\n3 2\n255\n":                  false, // grey, not colour
		"P6\n3 3\n255\n":                  false, // too short for 3 x 3
		"P6\n0 2\n255\n":                  false,
		"P6\n3":                           false,
		"":                                false,
	} {
		img, got := readPPM([]byte(header + pixels))
		if got != ok {
			t.Errorf("%q: ok %v, want %v", header, got, ok)
		} else if ok && (img.w != 3 || img.h != 2 || img.brightness(2, 1) != 3) {
			t.Errorf("%q: read %+v", header, img)
		}
	}
}

// grim gets the area around x, from 48 left of it (0 at the screen's left
// edge), and X keeps only its whole part
func TestBarAnchor(t *testing.T) {
	dir := t.TempDir()
	img := filepath.Join(dir, "grab.ppm")
	os.WriteFile(img, grab(96, 38, [2]int{20, 29}), 0o644)
	log := filepath.Join(dir, "log")
	script := "#!/bin/sh\necho \"$*\" >> " + log + "\ncat " + img + "\n"
	os.WriteFile(filepath.Join(dir, "grim"), []byte(script), 0o755)
	t.Setenv("PATH", dir+":/usr/bin")

	for _, tc := range []struct {
		args       []string
		area, want string
	}{
		{[]string{"512.7", "1042", "38.0"}, "464,1042 96x38", "488"}, // 464 + 24.5, to even
		{[]string{"30", "1042", "38"}, "0,1042 96x38", "24"},
	} {
		os.Remove(log)
		out := captureStdout(t, func() {
			if err := barAnchor(tc.args); err != nil {
				t.Fatal(err)
			}
		})
		calls, _ := os.ReadFile(log)
		if want := "-s 1 -t ppm -g " + tc.area + " -\n"; string(calls) != want {
			t.Errorf("%v: grim %q, want %q", tc.args, calls, want)
		}
		if out != tc.want+"\n" {
			t.Errorf("%v: printed %q, want %q", tc.args, out, tc.want)
		}
	}
}

// grim failing (no Wayland): x
func TestBarAnchorNoGrim(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	if out := captureStdout(t, func() { barAnchor([]string{"700.2", "0", "38"}) }); out != "700\n" {
		t.Errorf("printed %q", out)
	}
	if err := barAnchor([]string{"700"}); err == nil {
		t.Error("no usage error")
	}
}

func captureStdout(t *testing.T, f func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	old := os.Stdout
	os.Stdout = w
	defer func() { os.Stdout = old }()
	f()
	w.Close()
	data, _ := io.ReadAll(r)
	return string(data)
}
