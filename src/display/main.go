// primary-output and laptop-screen: the laptop's own screen and external
// displays.
//
// One binary, two names: install.sh builds it into
// ~/.local/bin/primary-output, and laptop-screen is a symlink to it. It looks
// at the name it was run as to know what to do.
//
//	primary-output [COMMAND...]   run by mango at login (config/mango/config.conf)
//	laptop-screen on|off|lid      run by mango on the lid switch and each reload
//
// primary-output is in primary.go, laptop-screen in laptop.go.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

func main() {
	name := filepath.Base(os.Args[0])
	var err error
	if name == "laptop-screen" {
		err = laptopScreen(os.Args[1:])
	} else {
		err = primaryOutput(os.Args[1:])
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", name, err)
		os.Exit(1)
	}
}

// The laptop's own screen, whatever it's called (eDP-1, eDP-2, LVDS-1,
// DSI-1...)
var internalName = regexp.MustCompile(`^(eDP|LVDS|DSI)`)

func isInternal(name string) bool {
	return internalName.MatchString(name)
}

// The names that aren't the laptop's own screen
func externals(names []string) []string {
	var ext []string
	for _, name := range names {
		if !isInternal(name) {
			ext = append(ext, name)
		}
	}
	return ext
}
