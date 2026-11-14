package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"
	"time"
)

// The tests run this test binary as record-toggle, record-status or
// cam-toggle (see rig.toggle, TestStatus and runCamToggle), with RECORD_RUN naming which. Then it runs
// main instead of the tests, with the waits shortened and the paths the
// tests give
func TestMain(m *testing.M) {
	if name := os.Getenv("RECORD_RUN"); name != "" {
		os.Args[0] = name
		countdown, barDelay = 100*time.Millisecond, 0
		if path := os.Getenv("RECORD_RENDER"); path != "" {
			renderNode = path
		}
		if path := os.Getenv("RECORD_PROC"); path != "" {
			procRoot = path
		}
		main()
		os.Exit(0)
	}
	os.Exit(m.Run())
}

// A fake /proc: wf-recorder processes started the given seconds after boot,
// another process, and an uptime of 1000.5 s
func fakeProc(t *testing.T, recorderStarts ...int) string {
	root := t.TempDir()
	write := func(rel, content string) {
		path := filepath.Join(root, rel)
		os.MkdirAll(filepath.Dir(path), 0o755)
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("uptime", "1000.50 2000.00\n")
	// A name with spaces and brackets, which stat shows as is
	write("5/comm", "a) b\n")
	write("5/stat", "5 (a) b) S"+fields(18)+" 100 0 0\n")
	write("self/comm", "wf-recorder\n") // not a pid: skipped
	for i, start := range recorderStarts {
		pid := strconv.Itoa(6 + i)
		write(pid+"/comm", "wf-recorder\n")
		// The start time is the 22nd field, in 100ths of a second
		write(pid+"/stat", pid+" (wf-recorder) S"+fields(18)+" "+strconv.Itoa(start*100)+" 0 0\n")
	}
	return root
}

// n fields of " 0", for the stat fields before the start time
func fields(n int) string {
	s := ""
	for range n {
		s += " 0"
	}
	return s
}

func TestRecordingFor(t *testing.T) {
	old := procRoot
	t.Cleanup(func() { procRoot = old })

	// The oldest one counts: started 500 s after boot, 1000.5 s in
	procRoot = fakeProc(t, 900, 500)
	if secs, ok := recordingFor(); !ok || secs != 500 {
		t.Errorf("got %d, %v; want 500, true", secs, ok)
	}
	procRoot = fakeProc(t)
	if _, ok := recordingFor(); ok {
		t.Error("recording with no wf-recorder")
	}
}

// record-toggle wakes every bar in the bars' folder with SIGUSR1. A sleep
// stands in for a bar: SIGUSR1 ends it
func TestWakeBars(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	bar := exec.Command("sleep", "10")
	if err := bar.Start(); err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(barsDir(), 0o755)
	os.WriteFile(filepath.Join(barsDir(), strconv.Itoa(bar.Process.Pid)), nil, 0o644)
	os.WriteFile(filepath.Join(barsDir(), "junk"), nil, 0o644)

	wakeBars()
	bar.Wait()
	if status, ok := bar.ProcessState.Sys().(syscall.WaitStatus); !ok || status.Signal() != syscall.SIGUSR1 {
		t.Errorf("the bar ended with %v, want SIGUSR1", bar.ProcessState)
	}
}
