package main

// cam-toggle [rotate|zoom-in|zoom-out|zoom-reset]: shows or hides the
// recording's webcam bubble (Quickshell, CameraWidget.qml). The options do
// what right-click, scroll and double-click do on it. It calls the bubble's
// functions (the IpcHandler with target "camera") with launcher-call.

import (
	"os"
	"path/filepath"
	"syscall"
)

func camToggle(args []string) error {
	// The first argument, if there is one
	arg := ""
	if len(args) > 0 {
		arg = args[0]
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	launcherCall := filepath.Join(home, ".local", "bin", "launcher-call")

	// Like bash's exec: launcher-call replaces this program, so its exit code
	// is cam-toggle's. It only returns if launcher-call can't be started
	return syscall.Exec(launcherCall, []string{launcherCall, "camera", cameraCall(arg)}, os.Environ())
}

// The CameraWidget.qml function for an argument
func cameraCall(arg string) string {
	switch arg {
	case "rotate":
		return "rotate"
	case "zoom-in":
		return "zoomIn"
	case "zoom-out":
		return "zoomOut"
	case "zoom-reset":
		return "zoomReset"
	default:
		return "toggle" // no argument, or one it doesn't know
	}
}
