package main

import (
	"os"
	"path/filepath"
	"testing"
)

// testdata/want.css is what the bash version wrote for testdata/theme.css
// (with the path in its first line made relative), plus the corners like
// border-top-left-radius, which bash missed. Its quirks are kept: a rule
// with no selector gives " {", and a declaration without its ; is dropped
func TestTheme(t *testing.T) {
	out := useTheme(t, "testdata/theme.css")
	if err := run(); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(out)
	want, _ := os.ReadFile("testdata/want.css")
	if string(got) != string(want) {
		t.Errorf("wrote\n%s\nwant\n%s", got, want)
	}
	if _, err := os.Stat(out + ".tmp"); !os.IsNotExist(err) {
		t.Error("left the .tmp file")
	}
}

// Points theme at file, and HOME at a new folder. Returns where radius.css
// goes
func useTheme(t *testing.T, file string) string {
	old := theme
	t.Cleanup(func() { theme = old })
	theme = file
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".config/gtk-3.0")
	os.MkdirAll(dir, 0o755)
	return filepath.Join(dir, "radius.css")
}

// Stow's link to the repo's radius.css stays a link, and the repo's file is
// the one written
func TestKeepsLink(t *testing.T) {
	out := useTheme(t, "testdata/theme.css")
	repo := filepath.Join(t.TempDir(), "radius.css")
	os.WriteFile(repo, []byte("old\n"), 0o644)
	if err := os.Symlink(repo, out); err != nil {
		t.Fatal(err)
	}
	if err := run(); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(out); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Errorf("%s isn't a link any more", out)
	}
	got, _ := os.ReadFile(repo)
	want, _ := os.ReadFile("testdata/want.css")
	if string(got) != string(want) {
		t.Errorf("the repo's file has\n%s", got)
	}
}

// No adw-gtk-theme: an error, and nothing written
func TestNoTheme(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "gtk.css")
	out := useTheme(t, missing)
	if err := run(); err == nil || err.Error() != "no "+missing+" (adw-gtk-theme)" {
		t.Errorf("error %v", err)
	}
	if _, err := os.Stat(out); !os.IsNotExist(err) {
		t.Error("wrote radius.css")
	}
}

func TestShrink(t *testing.T) {
	for value, want := range map[string]string{
		"6px":         "4px",
		"4px":         "4px",
		"4.5px":       "4px",
		"3.5px":       "3.5px",
		"98px":        "4px",
		"99px":        "99px",
		"9999px":      "9999px",
		"0":           "0",
		"8px 2px 0 0": "4px 2px 0 0",
		"50%":         "50%",
	} {
		if got := shrink(value); got != want {
			t.Errorf("shrink(%q) = %q, want %q", value, got, want)
		}
	}
}

// A last line without a newline, and a comment left open, like awk read them
func TestStripComments(t *testing.T) {
	for css, want := range map[string]string{
		"a /* b */ c":       "a  c",
		"a /* b":            "a ",
		"/* x */a/* y */b":  "ab",
		"no comments\n":     "no comments\n",
		"a */ not one /* b": "a */ not one ",
	} {
		if got := stripComments(css); got != want {
			t.Errorf("stripComments(%q) = %q, want %q", css, got, want)
		}
	}
}
