package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

// A fake home, runtime folder and PATH for record-toggle. Every stand-in logs
// "name args". pactl keeps the loaded modules in a file, like PipeWire would.
// The env given to toggle changes what the stand-ins do:
//
//	SLURP_FAILS=1  slurp is cancelled (Escape)
//	CANCEL=1       the countdown is cancelled (Escape over it)
//	EMPTY=1        wf-recorder records nothing
//	HOLD=1         wf-recorder keeps running (a recording in progress)
//	ACTION=name    the notification's button that's clicked
type rig struct {
	t                  *testing.T
	home, bin, runtime string
	render             string // a stand-in GPU, present by default
}

func newRig(t *testing.T) *rig {
	r := &rig{t: t, home: t.TempDir(), bin: t.TempDir(), runtime: t.TempDir()}
	r.render = filepath.Join(r.bin, "renderD128")
	os.WriteFile(r.render, nil, 0o644)

	modules := filepath.Join(r.bin, "modules")
	r.script(r.bin, "pactl", `case $1 in
list) cat `+modules+` 2>/dev/null ;;
load-module)
	n=$(cat `+r.bin+`/n 2>/dev/null || echo 100); n=$((n + 1)); echo $n > `+r.bin+`/n
	shift; printf '%s\t%s\n' "$n" "$*" >> `+modules+`; echo $n ;;
unload-module) grep -v "^$2	" `+modules+` > `+modules+`.tmp; mv `+modules+`.tmp `+modules+` ;;
get-default-sink) echo speakers ;;
esac`)
	r.script(r.bin, "slurp", `[ -n "$SLURP_FAILS" ] && exit 1; echo '0,0 100x100'`)
	r.script(r.bin, "notify-send", `case "$*" in *--wait*) echo "$ACTION" ;; esac`)
	r.script(r.bin, "wf-recorder", `[ -n "$HOLD" ] && while :; do sleep 0.05; done
for arg; do [ "$prev" = -f ] && out=$arg; prev=$arg; done
[ -n "$EMPTY" ] || echo video > "$out"`)
	r.script(r.bin, "ffmpegthumbnailer", `for arg; do [ "$prev" = -o ] && out=$arg; prev=$arg; done; echo thumb > "$out"`)
	for _, name := range []string{"xdg-open", "gdbus", "pkill"} {
		r.script(r.bin, name, "")
	}
	launcher := filepath.Join(r.home, ".local", "bin")
	os.MkdirAll(launcher, 0o755)
	// The countdown is told "<pid> <area>"; Escape there signals the pid
	r.script(launcher, "launcher-call", `[ "$1 $2" = "record countdown" ] && [ -n "$CANCEL" ] && kill -USR1 "${3%% *}"; :`)
	return r
}

func (r *rig) script(dir, name, body string) {
	script := "#!/bin/sh\necho \"" + name + " $*\" >> " + r.bin + "/log\n" + body + "\n"
	if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
		r.t.Fatal(err)
	}
}

func (r *rig) env(extra ...string) []string {
	env := append(os.Environ(),
		"PATH="+r.bin+":/usr/bin",
		"HOME="+r.home,
		"XDG_RUNTIME_DIR="+r.runtime,
		"RECORD_RENDER="+r.render,
		// With -race, a child would wait a second as it exits
		"GORACE=atexit_sleep_ms=0",
	)
	return append(env, extra...)
}

// Runs record-toggle with args; env sets the stand-ins' behaviour
func (r *rig) toggle(env []string, args ...string) (exitCode int) {
	cmd := exec.Command(os.Args[0], args...)
	cmd.Env = append(r.env(env...), "RECORD_RUN=record-toggle")
	cmd.Run()
	return cmd.ProcessState.ExitCode()
}

func (r *rig) log() []string {
	data, _ := os.ReadFile(filepath.Join(r.bin, "log"))
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimRight(string(data), "\n"), "\n")
}

// The modules left loaded
func (r *rig) modules() string {
	data, _ := os.ReadFile(filepath.Join(r.bin, "modules"))
	return string(data)
}

// Checks the log holds lines starting with each of wants, in that order
func (r *rig) ranInOrder(wants ...string) {
	r.t.Helper()
	log := r.log()
	i := 0
	for _, line := range log {
		if i < len(wants) && strings.HasPrefix(line, wants[i]) {
			i++
		}
	}
	if i < len(wants) {
		r.t.Errorf("didn't run %q (in that order) in:\n  %s", wants[i], strings.Join(log, "\n  "))
	}
}

func (r *rig) ran(prefix string) bool {
	for _, line := range r.log() {
		if strings.HasPrefix(line, prefix) {
			return true
		}
	}
	return false
}

// Starts a wf-recorder that keeps running, as during a recording
func (r *rig) recordingInProgress() {
	cmd := exec.Command(filepath.Join(r.bin, "wf-recorder"))
	cmd.Env = r.env("HOLD=1")
	if err := cmd.Start(); err != nil {
		r.t.Fatal(err)
	}
	r.t.Cleanup(func() { cmd.Process.Kill(); cmd.Wait() })
	for range 50 {
		if recording() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	r.t.Fatal("the stand-in wf-recorder isn't seen as running")
}

const (
	nullSink = "pactl load-module module-null-sink sink_name=record_mix sink_properties=device.description=Recording"
	micLoop  = "pactl load-module module-loopback source=@DEFAULT_SOURCE@ sink=record_mix latency_msec=20"
	deskLoop = "pactl load-module module-loopback source=speakers.monitor sink=record_mix latency_msec=20"
)

// A whole recording, with the camera, both sounds and the GPU, then Play
func TestRecord(t *testing.T) {
	r := newRig(t)
	if code := r.toggle([]string{"ACTION=default"}, "--both", "--fps=30", "--camera"); code != 0 {
		t.Fatalf("exit code %d", code)
	}
	files, _ := filepath.Glob(filepath.Join(r.home, "Videos", "Recordings", "rec-*.mp4"))
	if len(files) != 1 {
		t.Fatalf("recordings: %v\n%s", files, strings.Join(r.log(), "\n"))
	}
	file := files[0]
	if !regexp.MustCompile(`/rec-\d{8}-\d{6}\.mp4$`).MatchString(file) {
		t.Errorf("named %s", file)
	}
	r.ranInOrder(
		nullSink, micLoop, deskLoop,
		"launcher-call camera show",
		"notify-send Select area to record Drag an area, or click a screen for all of it",
		"slurp -o",
		"launcher-call record countdown ",
		"wf-recorder -g 0,0 100x100 -r 30 -c h264_vaapi -d "+r.render+" -p color_range=tv --audio=record_mix.monitor -f "+file,
		"launcher-call camera hide",
		"ffmpegthumbnailer -i "+file+" -o "+filepath.Join(r.runtime, "record-toggle-"+filepath.Base(file)+".png")+" -s 256",
		"notify-send -a Screen recording -i "+filepath.Join(r.runtime, "record-toggle-"+filepath.Base(file)+".png")+
			" --action=default=Play --action=folder=Show in folder --wait Recording saved "+filepath.Base(file),
		"xdg-open "+file,
	)
	// The countdown is told this run's pid and the area
	countdown := regexp.MustCompile(`^launcher-call record countdown \d+ 0,0 100x100$`)
	found := false
	for _, line := range r.log() {
		found = found || countdown.MatchString(line)
	}
	if !found {
		t.Error("countdown not given the pid and area")
	}
	if got := r.modules(); got != "" {
		t.Errorf("left loaded:\n%s", got)
	}
}

// No GPU: libx264rgb. The mic only, at the default 60 fps, no camera (but
// it's still hidden at the end, as the menu can turn it on meanwhile)
func TestRecordMicCPU(t *testing.T) {
	r := newRig(t)
	r.render = filepath.Join(r.bin, "no-gpu")
	r.toggle(nil, "--mic")
	r.ranInOrder(nullSink, micLoop, "wf-recorder -g 0,0 100x100 -r 60 -c libx264rgb --audio=record_mix.monitor -f ", "launcher-call camera hide")
	if r.ran(deskLoop) || r.ran("launcher-call camera show") {
		t.Errorf("ran too much:\n%s", strings.Join(r.log(), "\n"))
	}
}

// --fps=0 is uncapped: no -r. No sound: no loopback
func TestUncappedSilent(t *testing.T) {
	r := newRig(t)
	r.toggle(nil, "--none", "--fps=0")
	if r.ran("pactl load-module module-loopback") {
		t.Error("loaded a loopback for no sound")
	}
	r.ranInOrder(nullSink, "wf-recorder -g 0,0 100x100 -c h264_vaapi ")
}

// Escape while picking: the camera is hidden and the mix unloaded
func TestEscape(t *testing.T) {
	r := newRig(t)
	if code := r.toggle([]string{"SLURP_FAILS=1"}, "--both", "--camera"); code != 0 {
		t.Errorf("exit code %d", code)
	}
	r.ranInOrder("launcher-call camera show", "slurp -o", "launcher-call camera hide")
	if r.ran("wf-recorder") || r.ran("launcher-call record countdown") {
		t.Error("went on after Escape")
	}
	if got := r.modules(); got != "" {
		t.Errorf("left loaded:\n%s", got)
	}
}

// Escape over the countdown
func TestCountdownCancelled(t *testing.T) {
	r := newRig(t)
	if code := r.toggle([]string{"CANCEL=1"}, "--desktop", "--camera"); code != 0 {
		t.Errorf("exit code %d", code)
	}
	r.ranInOrder("launcher-call record countdown ", "launcher-call camera hide")
	if r.ran("wf-recorder") {
		t.Error("recorded after the countdown was cancelled")
	}
	if got := r.modules(); got != "" {
		t.Errorf("left loaded:\n%s", got)
	}
}

func TestNothingRecorded(t *testing.T) {
	r := newRig(t)
	if code := r.toggle([]string{"EMPTY=1"}, "--none"); code != 1 {
		t.Errorf("exit code %d, want 1", code)
	}
	r.ranInOrder("wf-recorder ", "notify-send -u critical Recording failed Nothing was recorded.")
	if r.ran("notify-send -a Screen recording") {
		t.Error("said it was saved")
	}
}

// A mix left from a run that didn't clean up is unloaded first; other
// modules stay
func TestLeftovers(t *testing.T) {
	r := newRig(t)
	os.WriteFile(filepath.Join(r.bin, "modules"), []byte(
		"7\tmodule-null-sink\tsink_name=record_mix sink_properties=device.description=Recording\n"+
			"8\tmodule-loopback\tsource=@DEFAULT_SOURCE@ sink=record_mix latency_msec=20\n"+
			"9\tmodule-loopback\tsource=other sink=elsewhere\n"), 0o644)
	r.toggle([]string{"SLURP_FAILS=1"}, "--none")
	r.ranInOrder("pactl unload-module 8", "pactl unload-module 7", nullSink)
	if got, want := r.modules(), "9\tmodule-loopback\tsource=other sink=elsewhere\n"; got != want {
		t.Errorf("left %q, want %q", got, want)
	}
}

// While recording, record-toggle (the bar's click, the toolbox) stops it
func TestStop(t *testing.T) {
	r := newRig(t)
	r.recordingInProgress()
	r.toggle(nil)
	if !r.ran("pkill -INT -x wf-recorder") {
		t.Errorf("didn't stop it:\n%s", strings.Join(r.log(), "\n"))
	}
	// Even with a sound option: it doesn't start another
	r.toggle(nil, "--both")
	if r.ran("slurp") {
		t.Error("started another recording")
	}
}

// Not recording, with no option: nothing to do
func TestNothingToStop(t *testing.T) {
	r := newRig(t)
	r.toggle(nil)
	r.toggle(nil, "--camera")
	if log := r.log(); log != nil {
		t.Errorf("ran %q", log)
	}
}

// The record menu changes the sound while recording: only the loopbacks
// change, record_mix stays
func TestLiveSound(t *testing.T) {
	r := newRig(t)
	sink := "7\tmodule-null-sink\tsink_name=record_mix sink_properties=device.description=Recording\n"
	os.WriteFile(filepath.Join(r.bin, "modules"), []byte(sink+
		"8\tmodule-loopback\tsource=@DEFAULT_SOURCE@ sink=record_mix latency_msec=20\n"), 0o644)

	// Not recording: nothing changes
	r.toggle(nil, "--live-sound=desktop")
	if r.ran("pactl") {
		t.Error("changed the sound while not recording")
	}

	r.recordingInProgress()
	r.toggle(nil, "--live-sound=desktop")
	want := sink + "101\tmodule-loopback source=speakers.monitor sink=record_mix latency_msec=20\n"
	if got := r.modules(); got != want {
		t.Errorf("loaded:\n%s\nwant:\n%s", got, want)
	}
	if r.ran("pkill") {
		t.Error("stopped the recording")
	}
}

func TestParseArgs(t *testing.T) {
	tests := []struct {
		args []string
		want options
	}{
		{nil, options{fps: 60}},
		{[]string{"--camera"}, options{fps: 60, camera: true}},
		{[]string{"--none", "--fps=120"}, options{start: true, sound: "none", fps: 120}},
		{[]string{"--fps=0", "--desktop"}, options{start: true, sound: "desktop"}},
		{[]string{"-m", "--fps=fast"}, options{start: true, sound: "mic"}},
		{[]string{"--sound"}, options{start: true, sound: "mic", fps: 60}},
		{[]string{"-b", "--camera"}, options{start: true, sound: "both", fps: 60, camera: true}},
		{[]string{"--live-sound=mic"}, options{fps: 60, liveSound: "mic"}},
		{[]string{"--other"}, options{start: true, sound: "none", fps: 60}},
	}
	for _, test := range tests {
		if got := parseArgs(test.args); got != test.want {
			t.Errorf("parseArgs(%q) = %+v, want %+v", test.args, got, test.want)
		}
	}
}
