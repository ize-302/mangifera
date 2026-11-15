// bar-anchor X BAR-TOP BAR-HEIGHT: prints the centre of the waybar module
// nearest X, so a popup can sit over it. Quickshell runs it
// (config/quickshell/launcher/shell.qml). Waybar doesn't tell where its
// modules are, so it grabs that part of the bar with grim and looks for
// bright pixels. Prints X when nothing is near.
package main

import (
	"bytes"
	"errors"
	"fmt"
	"math"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

const (
	// How far either side of X it looks
	reach = 48
	// The widest gap inside one module (between an icon and its text)
	join = 11
	// The farthest a module can be from X
	nearest = 24
)

func main() {
	if err := barAnchor(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "bar-anchor:", err)
		os.Exit(1)
	}
}

func barAnchor(args []string) error {
	if len(args) != 3 {
		return errors.New("usage: bar-anchor X BAR-TOP BAR-HEIGHT")
	}
	x, top, height := whole(args[0]), whole(args[1]), whole(args[2])
	left := max(x-reach, 0)

	// Without a grab (grim failing), nothing is near
	area := fmt.Sprintf("%d,%d %dx%d", left, top, reach*2, height)
	grab, _ := exec.Command("grim", "-s", "1", "-t", "ppm", "-g", area, "-").Output()
	fmt.Println(anchor(grab, x, left))
	return nil
}

// The number before any decimal point, as Quickshell passes reals: "512.5"
// is 512. Not a number is 0, like bash's arithmetic
func whole(arg string) int {
	n, _ := strconv.Atoi(strings.SplitN(arg, ".", 2)[0])
	return n
}

// The centre of the module nearest x in a grab of the bar from left, or x
func anchor(grab []byte, x, left int) int {
	img, ok := readPPM(grab)
	if !ok {
		return x
	}

	// The background: the darkest pixel of the middle row
	background := 256
	for px := range img.w {
		background = min(background, img.brightness(px, img.h/2))
	}
	// Which columns have ink: a pixel well above the background, away from
	// the top and bottom fifths
	ink := make([]bool, img.w+1)
	for px := range img.w {
		for py := img.h / 5; py < img.h-img.h/5; py++ {
			if img.brightness(px, py) > background+60 {
				ink[px] = true
				break
			}
		}
	}

	// Modules: runs of inked columns, joined across small gaps
	type run struct{ first, last int }
	var runs []run
	on := -1
	for px, inked := range ink {
		switch {
		case inked && on < 0:
			on = px
		case !inked && on >= 0:
			if n := len(runs); n > 0 && on-runs[n-1].last <= join {
				runs[n-1].last = px - 1
			} else {
				runs = append(runs, run{on, px - 1})
			}
			on = -1
		}
	}

	// The nearest within reach, the first of equals
	target := x - left
	best, mid := -1, 0.0
	for _, r := range runs {
		distance := 0
		if target < r.first || target > r.last {
			distance = min(abs(target-r.first), abs(target-r.last))
		}
		if distance <= nearest && (best < 0 || distance < best) {
			best = distance
			mid = float64(r.first+r.last) / 2
		}
	}
	if best < 0 {
		return x
	}
	// A centre halfway between two pixels goes to the even one
	return int(math.RoundToEven(float64(left) + mid))
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// A binary PPM (P6), 1 byte per colour
type ppm struct {
	w, h   int
	pixels []byte
}

// Reads grim's PPM: "P6", then width, height and the largest value,
// separated by white space and # comments, then one white space byte and
// the pixels
func readPPM(data []byte) (ppm, bool) {
	if !bytes.HasPrefix(data, []byte("P6")) {
		return ppm{}, false
	}
	at := 2
	var fields []int
	for len(fields) < 3 && at < len(data) {
		c := data[at]
		switch {
		case c == ' ' || (c >= '\t' && c <= '\r'):
			at++
		case c == '#':
			for at < len(data) && data[at] != '\n' {
				at++
			}
		default:
			value := 0
			for at < len(data) && data[at] >= '0' && data[at] <= '9' {
				value = value*10 + int(data[at]-'0')
				at++
			}
			fields = append(fields, value)
		}
	}
	if len(fields) < 3 {
		return ppm{}, false
	}
	w, h := fields[0], fields[1]
	start := at + 1
	if w <= 0 || h <= 0 || start+w*h*3 > len(data) {
		return ppm{}, false
	}
	return ppm{w, h, data[start : start+w*h*3]}, true
}

// The pixel's brightest colour
func (img ppm) brightness(px, py int) int {
	i := (py*img.w + px) * 3
	return int(max(img.pixels[i], img.pixels[i+1], img.pixels[i+2]))
}
