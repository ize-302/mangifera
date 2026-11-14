package main

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestElapsed(t *testing.T) {
	tests := map[int]string{0: "00:00", 65: "01:05", 3599: "59:59", 3600: "1:00:00", 3725: "1:02:05"}
	for secs, want := range tests {
		if got := elapsed(secs); got != want {
			t.Errorf("elapsed(%d) = %q, want %q", secs, got, want)
		}
	}
}

// Byte for byte what the bash version printed
func TestRecordingLine(t *testing.T) {
	want := `{"text": "󰑊 <span color=\"#ffffff\" font_features=\"tnum\">01:05</span>", "tooltip": "Recording the screen. Click to stop", "class": "recording"}`
	if got := recordingLine(65); got != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
}

// record-status as waybar runs it: an empty line, the time once woken while
// recording, and its file in the bars' folder until it's stopped. Files of
// record-status runs that are gone are removed
func TestStatus(t *testing.T) {
	proc := fakeProc(t)
	runtime := t.TempDir()
	bars := filepath.Join(runtime, "record-status")
	os.MkdirAll(bars, 0o755)
	for _, stale := range []string{"4194305", "junk"} { // no such process
		os.WriteFile(filepath.Join(bars, stale), nil, 0o644)
	}

	cmd := exec.Command(os.Args[0])
	cmd.Env = append(os.Environ(), "RECORD_RUN=record-status", "RECORD_PROC="+proc, "XDG_RUNTIME_DIR="+runtime, "GORACE=atexit_sleep_ms=0")
	out, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cmd.Process.Kill(); cmd.Wait() })
	lines := make(chan string)
	go func() {
		scanner := bufio.NewScanner(out)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		close(lines)
	}()
	next := func() string {
		select {
		case line := <-lines:
			return line
		case <-time.After(3 * time.Second):
			t.Fatal("no line from record-status")
			return ""
		}
	}

	if got := next(); got != notRecording {
		t.Errorf("first line %q, want %q", got, notRecording)
	}
	entries, _ := os.ReadDir(bars)
	if len(entries) != 1 || entries[0].Name() != strconv.Itoa(cmd.Process.Pid) {
		t.Errorf("bars' folder holds %v, want only its own pid", entries)
	}

	// A recording starts 500 s after boot, 1000.5 s in, and record-toggle
	// wakes the bar
	os.MkdirAll(filepath.Join(proc, "9"), 0o755)
	os.WriteFile(filepath.Join(proc, "9", "comm"), []byte("wf-recorder\n"), 0o644)
	os.WriteFile(filepath.Join(proc, "9", "stat"), []byte("9 (wf-recorder) S"+fields(18)+" 50000 0 0\n"), 0o644)
	cmd.Process.Signal(syscall.SIGUSR1)
	if got := next(); !strings.Contains(got, ">08:20</span>") {
		t.Errorf("after waking, %q, want 08:20", got)
	}
	// And it keeps ticking without being woken
	if got := next(); !strings.Contains(got, `"class": "recording"`) {
		t.Errorf("a second later, %q", got)
	}

	cmd.Process.Signal(syscall.SIGTERM)
	cmd.Wait()
	if entries, _ := os.ReadDir(bars); len(entries) != 0 {
		t.Errorf("left %v behind", entries)
	}
}
