// launcher-call and the commands that open the Quickshell launcher's menus.
//
// One binary, many names: install.sh builds it into
// ~/.local/bin/launcher-call, and app-menu, control-panel, power-menu and
// the rest are symlinks to it. It looks at the name it was run as to know
// what to do.
//
//	launcher-call <target> <function> [argument]
//	app-menu | clipboard-menu | keybind-menu
//	date-panel | notification-center | toolbox [--pointer]
//	control-panel [--pointer] [section]
//	scratchpad-menu [--tap|--open|--close]
//	record-menu
//	power-menu [lock|logout|sleep|reboot|shutdown]
//	lock-screen
//
// launcher-call calls a function of the launcher daemon over its socket,
// like `qs -c launcher ipc call` but with no Qt client to start, so menus
// open at once. It starts the daemon if needed.
package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const logoutSound = "/usr/share/sounds/freedesktop/stereo/service-logout.oga"

func main() {
	name := filepath.Base(os.Args[0])
	os.Exit(run(name, os.Args[1:]))
}

func run(name string, args []string) int {
	switch name {
	case "lock-screen":
		return lockScreen()
	case "power-menu":
		if len(args) > 0 {
			return powerAction(args[0])
		}
	case "record-menu":
		return launcherCall(callFor(name, args, recording())...)
	}
	return launcherCall(callFor(name, args, false)...)
}

// The daemon call a command makes: "<target> <function> [argument]".
// recording is whether wf-recorder is running, for record-menu.
func callFor(name string, args []string, recording bool) []string {
	first := ""
	if len(args) > 0 {
		first = args[0]
	}
	pointer := first == "--pointer"

	switch name {
	case "app-menu":
		return []string{"launcher", "toggleAppMenu"}
	case "clipboard-menu":
		return []string{"clipboard", "toggleClipboardMenu"}
	case "keybind-menu":
		return []string{"keybinds", "toggleKeybindMenu"}
	case "power-menu":
		return []string{"power", "togglePowerMenu"}
	case "date-panel":
		return withPointer("datePanel", "toggleDatePanel", pointer)
	case "notification-center":
		return withPointer("notificationCenter", "toggleNotificationCenter", pointer)
	case "toolbox":
		return withPointer("toolbox", "toggleToolbox", pointer)
	case "record-menu":
		// While recording, it changes the running one (sound, camera) or stops it
		if recording {
			return []string{"record", "toggleLiveMenu"}
		}
		return []string{"record", "toggleRecordMenu"}
	case "scratchpad-menu":
		switch first {
		case "--tap": // the second of two quick Super taps toggles it
			return []string{"scratchpad", "tap"}
		case "--open":
			return []string{"scratchpad", "openScratchpadMenu"}
		case "--close":
			return []string{"scratchpad", "closeScratchpadMenu"}
		}
		return []string{"scratchpad", "toggleScratchpadMenu"}
	case "control-panel":
		// control-panel [--pointer] [section]: the sound popup, or a
		// section ("Network", "Bluetooth")
		at := ""
		if pointer {
			at = "AtPointer"
			args = args[1:]
		}
		if len(args) > 0 && args[0] != "" {
			return []string{"controlPanel", "openSection" + at, args[0]}
		}
		return []string{"controlPanel", "toggleControlPanel" + at}
	}
	// launcher-call, or any other name: pass the arguments through
	return args
}

// --pointer centres the menu over the bar module under the pointer
func withPointer(target, function string, pointer bool) []string {
	if pointer {
		function += "AtPointer"
	}
	return []string{target, function}
}

// --- calling the daemon -------------------------------------------------------

func socketPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = "/run/user/" + strconv.Itoa(os.Getuid())
	}
	return filepath.Join(dir, "mangifera-launcher.sock")
}

// Sends the call, starting the daemon if none is running. Returns the exit
// code: 0 if the call got through.
func launcherCall(call ...string) int {
	socket := socketPath()
	if send(socket, call) == nil {
		return 0
	}

	// Only when none is running: a busy daemon that missed the call above
	// would otherwise get a second one beside it, splitting menus from
	// notifications
	if findProcess(isLauncherDaemon) {
		return 1
	}

	// -d starts it in the background and returns
	if exec.Command("qs", "-c", "launcher", "-d").Run() == nil {
		for range 20 {
			if send(socket, call) == nil {
				return 0
			}
			time.Sleep(100 * time.Millisecond)
		}
	}
	return 1
}

// Writes the call as one line to the daemon's socket. The daemon closes
// the connection once it has read it; that's waited for, up to a second.
func send(socket string, call []string) error {
	conn, err := net.DialTimeout("unix", socket, time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	if _, err := io.WriteString(conn, strings.Join(call, " ")+"\n"); err != nil {
		return err
	}
	conn.(*net.UnixConn).CloseWrite()
	conn.SetReadDeadline(time.Now().Add(time.Second))
	io.Copy(io.Discard, conn) // until the daemon closes, or the deadline
	return nil
}

// --- power menu and lock screen -----------------------------------------------

// Carries out a power menu entry. Returns the exit code of the last command.
func powerAction(action string) int {
	switch action {
	case "lock":
		return lockScreen()
	case "logout":
		return runAll([]string{"paplay", logoutSound}, []string{"mmsg", "dispatch", "quit"})
	case "sleep":
		return runAll([]string{"systemctl", "suspend"})
	case "reboot":
		return runAll([]string{"paplay", logoutSound}, []string{"systemctl", "reboot"})
	case "shutdown":
		return runAll([]string{"paplay", logoutSound}, []string{"systemctl", "poweroff", "-i"})
	}
	return 0
}

// Runs commands in order, stopping at the first that fails (like `a && b`).
// Returns the exit code of the last one run.
func runAll(commands ...[]string) int {
	for _, command := range commands {
		cmd := exec.Command(command[0], command[1:]...)
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		if code := exitCode(cmd.Run()); code != 0 {
			return code
		}
	}
	return 0
}

// Locks with the Quickshell locker, falling back to swaylock
func lockScreen() int {
	_, qsErr := exec.LookPath("qs")
	_, shellErr := os.Stat(filepath.Join(os.Getenv("HOME"), ".config/quickshell/lock/shell.qml"))
	if qsErr == nil && shellErr == nil {
		if findProcess(isLocker) {
			return 0 // already locked
		}
		if runAll([]string{"qs", "-c", "lock", "-d"}) == 0 {
			return 0
		}
	}

	// Replaces this process, like bash's exec
	swaylock, err := exec.LookPath("swaylock")
	if err != nil {
		fmt.Fprintln(os.Stderr, "lock-screen: swaylock:", err)
		return 127
	}
	err = syscall.Exec(swaylock, []string{"swaylock", "-f", "-c", "000000"}, os.Environ())
	fmt.Fprintln(os.Stderr, "lock-screen:", err)
	return 1
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode()
	}
	return 127 // didn't start, e.g. not installed
}

// --- processes ----------------------------------------------------------------
//
// What pgrep did, by reading /proc

type process struct {
	uid     int
	name    string   // like pgrep's process name: /proc/<pid>/comm
	cmdline []string // the command and its arguments
}

// Your launcher daemon (pgrep -u $UID -xf 'qs -c launcher -d')
func isLauncherDaemon(p process) bool {
	return p.uid == os.Getuid() && strings.Join(p.cmdline, " ") == "qs -c launcher -d"
}

// Your locker (pgrep -u $UID -f 'qs -c lock')
func isLocker(p process) bool {
	return p.uid == os.Getuid() && strings.Contains(strings.Join(p.cmdline, " "), "qs -c lock")
}

// Whether a screen recording is running (pgrep -x wf-recorder)
func recording() bool {
	return findProcess(func(p process) bool { return p.name == "wf-recorder" })
}

// Whether any process other than this one matches
func findProcess(match func(process) bool) bool {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return false
	}
	self := os.Getpid()
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil || pid == self {
			continue // not a process
		}
		p, ok := readProcess(filepath.Join("/proc", entry.Name()))
		if ok && match(p) {
			return true
		}
	}
	return false
}

func readProcess(dir string) (process, bool) {
	info, err := os.Stat(dir)
	if err != nil {
		return process{}, false // it exited
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return process{}, false
	}
	comm, _ := os.ReadFile(filepath.Join(dir, "comm"))
	cmdline, _ := os.ReadFile(filepath.Join(dir, "cmdline"))
	return process{
		uid:     int(stat.Uid),
		name:    strings.TrimSuffix(string(comm), "\n"),
		cmdline: splitCmdline(cmdline),
	}, true
}

// /proc/<pid>/cmdline holds the arguments, each ending in a 0 byte
func splitCmdline(data []byte) []string {
	text := strings.TrimSuffix(string(data), "\x00")
	if text == "" {
		return nil
	}
	return strings.Split(text, "\x00")
}
