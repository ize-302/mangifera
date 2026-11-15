package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// The tests run this test binary as mango-reload, with RELOAD_RUN set
func TestMain(m *testing.M) {
	if os.Getenv("RELOAD_RUN") != "" {
		main()
		os.Exit(0)
	}
	os.Exit(m.Run())
}

// Runs mango-reload with stand-ins for pkill, waybar, notify-send and mmsg,
// which prints answer. Returns their calls, waybar's last as it starts on
// its own
func reload(t *testing.T, answer string) []string {
	bin := t.TempDir()
	log := filepath.Join(bin, "log")
	for name, extra := range map[string]string{
		"pkill":       "",
		"notify-send": "",
		// Its session, to check it leads its own
		"waybar": `; echo "waybar session $( [ "$(ps -o sid= -p $$ | tr -d ' ')" = $$ ] && echo own || echo shared)" >> ` + log,
		"mmsg":   `; printf '%s\n' '` + answer + `'`,
	} {
		script := "#!/bin/sh\necho \"" + name + " $*\" >> " + log + extra + "\n"
		os.WriteFile(filepath.Join(bin, name), []byte(script), 0o755)
	}
	home := t.TempDir()

	cmd := testCommand(t)
	cmd.Env = append(os.Environ(), "RELOAD_RUN=1", "PATH="+bin+":/usr/bin", "HOME="+home)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %s", err, out)
	}

	var calls []string
	for range 100 {
		data, _ := os.ReadFile(log)
		calls = strings.Split(strings.TrimSpace(string(data)), "\n")
		if slices.ContainsFunc(calls, func(c string) bool { return strings.HasPrefix(c, "waybar session") }) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	// waybar runs alongside, so its lines can land anywhere
	var rest, bar []string
	for _, c := range calls {
		if strings.HasPrefix(c, "waybar") {
			bar = append(bar, c)
		} else {
			rest = append(rest, c)
		}
	}
	if want := []string{"waybar ", "waybar session own"}; !slices.Equal(bar, want) {
		t.Errorf("waybar: %q, want %q", bar, want)
	}
	for i := range rest {
		rest[i] = strings.ReplaceAll(rest[i], home, "~")
	}
	return rest
}

func TestReloaded(t *testing.T) {
	got := reload(t, `{"success":true}`)
	want := []string{
		"pkill -x waybar",
		"mmsg dispatch reload_config",
		"notify-send -a mango -i ~/.local/share/mangifera/mango.svg -t 2000 Config reloaded",
	}
	if !slices.Equal(got, want) {
		t.Errorf("ran\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestReloadFailed(t *testing.T) {
	for _, answer := range []string{`{"success":false,"error":"bad line 12"}`, ""} {
		got := reload(t, answer)
		want := []string{
			"pkill -x waybar",
			"mmsg dispatch reload_config",
			"notify-send -a mango -i ~/.local/share/mangifera/mango.svg -u critical Config reload failed",
		}
		if !slices.Equal(got, want) {
			t.Errorf("%q: ran\n%s\nwant\n%s", answer, strings.Join(got, "\n"), strings.Join(want, "\n"))
		}
	}
}

func testCommand(t *testing.T) *exec.Cmd {
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	return exec.Command(exe, "-test.run=^$")
}
