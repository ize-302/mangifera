// network-info: Wi-Fi helpers for the control panel, via nmcli (or iwctl with
// the iwd backend, since iwd only gets passwords from a secret agent).
//
//	network-info show <ssid>               details as JSON
//	network-info autoconnect <uuid> yes|no
//	network-info join <ssid>               hidden network, password on stdin
//	network-info connect <ssid>            password on stdin
//
// install.sh builds this into ~/.local/bin/network-info.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		usage()
	}
	switch {
	case args[0] == "show" && len(args) == 2:
		show(args[1])
	case args[0] == "connect" && len(args) == 2:
		connect(args[1])
	case args[0] == "join" && len(args) == 2:
		join(args[1])
	case args[0] == "autoconnect" && len(args) == 3 && (args[2] == "yes" || args[2] == "no"):
		setAutoconnect(args[1], args[2])
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: network-info show <ssid> | autoconnect <uuid> yes|no | join <ssid> | connect <ssid>")
	os.Exit(1)
}

// --- show -------------------------------------------------------------------

// Details is what `show` prints. Fields with omitempty are left out when
// unknown; pointers tell "unknown" (nil) apart from a real 0 or false.
type Details struct {
	SSID        string   `json:"ssid"`
	UUID        string   `json:"uuid,omitempty"`
	Autoconnect *bool    `json:"autoconnect,omitempty"`
	Signal      *int     `json:"signal,omitempty"`
	Frequency   *string  `json:"frequency,omitempty"`
	Rate        *string  `json:"rate,omitempty"`
	Security    *string  `json:"security,omitempty"`
	Device      string   `json:"device,omitempty"`
	Connected   bool     `json:"connected"`
	MAC         string   `json:"mac,omitempty"`
	IP          string   `json:"ip,omitempty"`
	Gateway     string   `json:"gateway,omitempty"`
	DNS         []string `json:"dns,omitempty"`
}

// An access point from `nmcli device wifi list`
type accessPoint struct {
	inUse     bool
	signal    int
	frequency string
	rate      string
	security  string
	device    string
}

func show(ssid string) {
	details := Details{SSID: ssid}

	if uuid, autoconnect, ok := savedConnection(ssid); ok {
		details.UUID = uuid
		details.Autoconnect = &autoconnect
	}

	// The access point in use, else the strongest
	var best *accessPoint
	for _, line := range lines(output("nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,FREQ,RATE,SECURITY,DEVICE", "device", "wifi", "list", "--rescan", "no")) {
		f := fields(line, 7)
		if f[1] != ssid {
			continue
		}
		signal, _ := strconv.Atoi(f[2]) // 0 if missing
		ap := accessPoint{
			inUse:     f[0] == "*",
			signal:    signal,
			frequency: f[3],
			rate:      f[4],
			security:  f[5],
			device:    f[6],
		}
		if best == nil || better(ap, *best) {
			best = &ap
		}
	}
	if best != nil {
		security := best.security
		if security == "" {
			security = "Open"
		}
		details.Signal = &best.signal
		details.Frequency = &best.frequency
		details.Rate = &best.rate
		details.Security = &security
		if best.inUse {
			details.Connected = true
			details.Device = best.device
		}
	}

	if details.Connected {
		// `device show` doesn't escape ':' in values, so split on the first one
		for _, line := range lines(output("nmcli", "-t", "-f", "GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", details.Device)) {
			key, value, _ := strings.Cut(line, ":")
			switch {
			case key == "GENERAL.HWADDR":
				details.MAC = value
			case strings.HasPrefix(key, "IP4.ADDRESS"):
				if details.IP == "" {
					details.IP, _, _ = strings.Cut(value, "/") // drop the /24
				}
			case key == "IP4.GATEWAY":
				details.Gateway = value
			case strings.HasPrefix(key, "IP4.DNS"):
				details.DNS = append(details.DNS, value)
			}
		}
	}

	printJSON(details)
}

// Whether a beats b: in use first, then the stronger signal
func better(a, b accessPoint) bool {
	if a.inUse != b.inUse {
		return a.inUse
	}
	return a.signal > b.signal
}

// The saved connection for ssid: its UUID and whether it autoconnects
func savedConnection(ssid string) (uuid string, autoconnect bool, ok bool) {
	for _, line := range lines(output("nmcli", "-t", "-f", "UUID,TYPE,AUTOCONNECT", "connection", "show")) {
		f := fields(line, 3)
		if f[1] != "802-11-wireless" {
			continue
		}
		// -g escapes the value like -t: a ':' in the name comes as '\:'
		setting := output("nmcli", "-g", "802-11-wireless.ssid", "connection", "show", f[0])
		if strings.Join(fields(strings.TrimSpace(setting), 0), ":") == ssid {
			return f[0], f[2] == "yes", true
		}
	}
	return "", false, false
}

// --- autoconnect ------------------------------------------------------------

func setAutoconnect(uuid, value string) {
	if code, stderr := run("nmcli", "connection", "modify", uuid, "connection.autoconnect", value); code != 0 {
		fmt.Fprintln(os.Stderr, strings.TrimSpace(stderr))
		os.Exit(1)
	}
}

// --- join and connect -------------------------------------------------------

// nmcli and iwctl only take the password as an argument, so it's briefly in `ps`

// Joins a hidden network
func join(ssid string) {
	password := readPassword()
	device := wifiDevice()
	if iwdBackend() {
		report(iwctlStation(device, password, "connect-hidden", ssid))
		return
	}
	args := []string{"device", "wifi", "connect", ssid, "ifname", device, "hidden", "yes"}
	if password != "" {
		args = append(args, "password", password)
	}
	report(run("nmcli", args...))
}

func connect(ssid string) {
	password := readPassword()
	device := wifiDevice()
	saved, _, isSaved := savedConnection(ssid)
	if isSaved {
		code, stderr := run("nmcli", "connection", "modify", saved, "802-11-wireless-security.psk", password)
		if code != 0 {
			report(code, stderr)
			return
		}
	}
	switch {
	case iwdBackend():
		report(iwctlStation(device, password, "connect", ssid))
	case isSaved:
		report(run("nmcli", "connection", "up", saved))
	default:
		report(run("nmcli", "device", "wifi", "connect", ssid, "ifname", device, "password", password))
	}
}

// The first line of stdin, without its newline
func readPassword() string {
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	return strings.TrimSuffix(line, "\n")
}

// The Wi-Fi interface, like wlan0; exits if there's none
func wifiDevice() string {
	for _, line := range lines(output("nmcli", "-t", "-f", "DEVICE,TYPE", "device")) {
		f := fields(line, 2)
		if f[1] == "wifi" {
			return f[0]
		}
	}
	fmt.Fprintln(os.Stderr, "No Wi-Fi device")
	os.Exit(1)
	return ""
}

func iwdBackend() bool {
	code, _ := run("systemctl", "is-active", "--quiet", "iwd")
	return code == 0
}

var ansiColor = regexp.MustCompile(`\x1b\[[0-9;]*m`)

// Runs `iwctl station <device> <args...>`, returning its exit code and message
func iwctlStation(device, password string, args ...string) (int, string) {
	command := []string{"--dont-ask"}
	if password != "" {
		command = append(command, "--passphrase", password)
	}
	command = append(command, "station", device)
	command = append(command, args...)

	cmd := exec.Command("iwctl", command...)
	out, err := cmd.CombinedOutput()
	code := exitCode(err)
	message := strings.TrimSpace(ansiColor.ReplaceAllString(string(out), ""))
	if code == 0 && err != nil {
		message = err.Error()
	}
	if code != 0 && (message == "Operation failed" || message == "Operation aborted") {
		message = "Couldn't connect. Check the password."
	}
	return code, message
}

// What the control panel reads after join and connect
type result struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

func report(code int, message string) {
	if code == 0 {
		printJSON(result{OK: true})
		return
	}
	message = strings.TrimPrefix(strings.TrimSpace(message), "Error: ")
	if message == "" {
		message = "Couldn't connect"
	}
	printJSON(result{OK: false, Error: message})
}

// --- helpers ----------------------------------------------------------------

// Runs a command, returning its exit code and stderr. Stdout is dropped.
func run(name string, args ...string) (int, string) {
	var stderr bytes.Buffer
	cmd := exec.Command(name, args...)
	cmd.Stderr = &stderr
	err := cmd.Run()
	code := exitCode(err)
	if code != 0 && stderr.Len() == 0 {
		return code, err.Error() // e.g. the command isn't installed
	}
	return code, stderr.String()
}

// Runs a command and returns its stdout, or "" if it fails
func output(name string, args ...string) string {
	out, _ := exec.Command(name, args...).Output()
	return string(out)
}

// 0 when err is nil, the command's exit code when it ran and failed, else 1
func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return 1
}

// Splits text into lines, dropping the empty last one
func lines(text string) []string {
	text = strings.TrimSuffix(text, "\n")
	if text == "" {
		return nil
	}
	return strings.Split(text, "\n")
}

// Splits a line of nmcli -t output on ':', but not on '\:'. nmcli writes
// a ':' inside a value as '\:' and a '\' as '\\'. The result has at least
// min fields, padded with "", so f[i] never goes out of range.
func fields(line string, min int) []string {
	var f []string
	var current strings.Builder
	for i := 0; i < len(line); i++ {
		c := line[i]
		switch {
		case c == '\\' && i+1 < len(line) && (line[i+1] == ':' || line[i+1] == '\\'):
			current.WriteByte(line[i+1])
			i++ // skip the escaped character
		case c == ':':
			f = append(f, current.String())
			current.Reset()
		default:
			current.WriteByte(c)
		}
	}
	f = append(f, current.String())
	for len(f) < min {
		f = append(f, "")
	}
	return f
}

func printJSON(v any) {
	out, err := json.Marshal(v)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(string(out))
}
