package main

// record-toggle [--none|--desktop|--mic|--both] [--camera] [--fps=N]
// record-toggle --live-sound=<none|desktop|mic|both>
//
// Starts recording a slurp-picked area to ~/Videos/Recordings, or stops the
// running one. --desktop adds the playing audio, --mic (or --sound) the
// default mic, --both the two mixed. --camera shows the webcam bubble
// (CameraWidget.qml) from picking the area until the recording stops. --fps
// sets a constant frame rate, 60 by default; 0 leaves it uncapped. With no
// option it only stops. --live-sound changes the running recording's sound
// (from the record menu, RecordMenu.qml), without stopping it.

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// The tests shorten or move these
var (
	// The 3-2-1 over the area (RecordCountdown.qml)
	countdown = 3200 * time.Millisecond
	// For wf-recorder to start before the bar looks for it
	barDelay = 300 * time.Millisecond
	// The GPU, for encoding
	renderNode = "/dev/dri/renderD128"
)

type options struct {
	start     bool   // a sound option was given: start recording
	sound     string // none, desktop, mic or both
	camera    bool
	fps       int // 0: uncapped
	liveSound string
}

func parseArgs(args []string) options {
	o := options{fps: 60}
	var rest []string
	for _, arg := range args {
		switch {
		case arg == "--camera":
			o.camera = true
		case strings.HasPrefix(arg, "--fps="):
			// Not a number counts as 0, uncapped, like the bash version
			o.fps, _ = strconv.Atoi(strings.TrimPrefix(arg, "--fps="))
		case strings.HasPrefix(arg, "--live-sound="):
			o.liveSound = strings.TrimPrefix(arg, "--live-sound=")
		default:
			rest = append(rest, arg)
		}
	}
	if len(rest) > 0 {
		o.start = true
		switch rest[0] {
		case "-m", "--mic", "-s", "--sound":
			o.sound = "mic"
		case "-d", "--desktop":
			o.sound = "desktop"
		case "-b", "--both":
			o.sound = "both"
		default:
			o.sound = "none"
		}
	}
	return o
}

func recordToggle(args []string) error {
	o := parseArgs(args)
	switch {
	case o.liveSound != "":
		if recording() {
			mix(o.liveSound)
		}
		return nil
	case recording():
		// The run that started it notices, and does the rest
		exec.Command("pkill", "-INT", "-x", "wf-recorder").Run()
		return nil
	case o.start:
		return record(o)
	}
	return nil
}

// Picks the area, counts down, records until wf-recorder is stopped, then
// notifies
func record(o options) error {
	// Left over from a run that didn't get to clean up
	unload()
	defer unload()
	// Cleans up when killed too, not only on returning
	killed := make(chan os.Signal, 1)
	signal.Notify(killed, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		<-killed
		unload()
		launcherCall("camera", "hide")
		os.Exit(1)
	}()

	pactl("load-module", "module-null-sink", "sink_name=record_mix", "sink_properties=device.description=Recording")
	mix(o.sound)

	// Shown while picking, so it can be placed in the area first
	camera := func(call string) {
		if o.camera {
			launcherCall("camera", call)
		}
	}
	camera("show")
	exec.Command("notify-send", "Select area to record", "Drag an area, or click a screen for all of it").Run()
	out, err := exec.Command("slurp", "-o").Output()
	if err != nil { // Escape
		camera("hide")
		return nil
	}
	area := strings.TrimSpace(string(out))

	// 3-2-1 over the area, gone before recording starts. Escape there sends
	// SIGUSR1, which cancels. Later ones are ignored
	cancel := make(chan os.Signal, 1)
	signal.Notify(cancel, syscall.SIGUSR1)
	launcherCall("record", "countdown", fmt.Sprintf("%d %s", os.Getpid(), area))
	select {
	case <-time.After(countdown):
	case <-cancel:
		camera("hide")
		return nil
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	dir := filepath.Join(home, "Videos", "Recordings")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	// Not in the layout: Go would read the 4 of .mp4 as the minutes
	file := filepath.Join(dir, time.Now().Format("rec-20060102-150405")+".mp4")

	wfRecorder := exec.Command("wf-recorder", wfRecorderArgs(area, o.fps, file)...)
	wfRecorder.Stdout, wfRecorder.Stderr = os.Stdout, os.Stderr
	if err := wfRecorder.Start(); err == nil {
		time.Sleep(barDelay)
		wakeBars()
		wfRecorder.Wait()
	} else {
		fmt.Fprintln(os.Stderr, "record-toggle: wf-recorder:", err)
	}

	unload()
	// Whether or not it started with the camera: the menu can turn it on
	// while recording
	launcherCall("camera", "hide")
	wakeBars()

	if info, err := os.Stat(file); err != nil || info.Size() == 0 {
		exec.Command("notify-send", "-u", "critical", "Recording failed", "Nothing was recorded.").Run()
		return errors.New("nothing was recorded")
	}
	notifySaved(file)
	return nil
}

func wfRecorderArgs(area string, fps int, file string) []string {
	args := []string{"-g", area}
	// Left alone it writes a frame per screen update, up to the refresh rate,
	// and sites such as X refuse anything over 60 fps
	if fps > 0 {
		args = append(args, "-r", strconv.Itoa(fps))
	}
	// Encode on the GPU: libx264rgb only managed ~33 fps of a moving screen,
	// and starving the CPU lost audio, so the sound drifted ahead of the
	// picture. It also makes plain 4:2:0 H.264 that any player decodes
	if _, err := os.Stat(renderNode); err == nil {
		// The GPU writes video range (16-235) whatever wf-recorder asks for,
		// which it then labels full range, so players showed it washed out.
		// Label it as what it is
		args = append(args, "-c", "h264_vaapi", "-d", renderNode, "-p", "color_range=tv")
	} else {
		args = append(args, "-c", "libx264rgb")
	}
	// The sound comes from record_mix (see mix)
	return append(args, "--audio=record_mix.monitor", "-f", file)
}

// Notifies that file was saved, with a thumbnail, and does what its clicked
// button says. notify-send --wait prints the button's name once one is
// clicked
func notifySaved(file string) {
	thumb := filepath.Join(runtimeDir(), "record-toggle-"+filepath.Base(file)+".png")
	if exec.Command("ffmpegthumbnailer", "-i", file, "-o", thumb, "-s", "256").Run() != nil {
		thumb = "video-x-generic"
	}

	// Gives up waiting after an hour, like the bash version
	ctx, cancel := context.WithTimeout(context.Background(), time.Hour)
	defer cancel()
	out, _ := exec.CommandContext(ctx, "notify-send", "-a", "Screen recording", "-i", thumb,
		"--action=default=Play", "--action=folder=Show in folder", "--wait",
		"Recording saved", filepath.Base(file)).Output()

	switch strings.TrimSpace(string(out)) {
	case "default": // the notification itself was clicked
		exec.Command("xdg-open", file).Run()
	case "folder":
		exec.Command("gdbus", "call", "--session",
			"--dest", "org.freedesktop.FileManager1",
			"--object-path", "/org/freedesktop/FileManager1",
			"--method", "org.freedesktop.FileManager1.ShowItems",
			"['file://"+file+"']", "").Run()
	}
}

// Calls a launcher function, as in `launcher-call camera show`
func launcherCall(args ...string) {
	home, _ := os.UserHomeDir()
	exec.Command(filepath.Join(home, ".local", "bin", "launcher-call"), args...).Run()
}

// Every recording takes its sound from a sink of its own, record_mix, with
// the mic and the playing audio looped into it as picked. wf-recorder takes
// one source, fixed when it starts, so this way the sound can change while
// recording. With no sound it records the sink's silence.

// Runs pactl and returns what it printed
func pactl(args ...string) string {
	out, _ := exec.Command("pactl", args...).Output()
	return string(out)
}

// Ids of the loaded modules of a kind feeding (or being) record_mix, matched
// by their arguments, so any run finds the ones the starting run loaded
func mixModules(kind string) []string {
	var ids []string
	for _, line := range strings.Split(pactl("list", "modules", "short"), "\n") {
		// "<id>	<module name>	<arguments>"
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[1] == kind && strings.Contains(line, "record_mix") {
			ids = append(ids, fields[0])
		}
	}
	return ids
}

// Feeds record_mix the given sound: none, desktop, mic or both
func mix(sound string) {
	for _, id := range mixModules("module-loopback") {
		pactl("unload-module", id)
	}
	defaultSink := strings.TrimSpace(pactl("get-default-sink"))
	if sound == "mic" || sound == "both" {
		pactl("load-module", "module-loopback", "source=@DEFAULT_SOURCE@", "sink=record_mix", "latency_msec=20")
	}
	if sound == "desktop" || sound == "both" {
		pactl("load-module", "module-loopback", "source="+defaultSink+".monitor", "sink=record_mix", "latency_msec=20")
	}
}

// Unloads record_mix and what feeds it
func unload() {
	for _, id := range append(mixModules("module-loopback"), mixModules("module-null-sink")...) {
		pactl("unload-module", id)
	}
}
