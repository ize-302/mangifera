package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"slices"
	"strings"
)

// An external drive and the filesystems on it
type drive struct {
	// The whole disk, like /dev/sdb
	Disk string
	// Its first filesystem's label, or its model
	Name string
	// Like "29.3 GB"
	Size string
	// Whether udisks can power it off on eject: USB sticks and disks can,
	// a card reader shouldn't be (it would miss the next card)
	PowerOff    bool
	Filesystems []filesystem
}

type filesystem struct {
	Path       string
	Fstype     string
	Mountpoint string
}

// One line of `lsblk --json --list`
type device struct {
	Name       string `json:"name"`
	Path       string `json:"path"`
	Parent     string `json:"pkname"`
	Type       string `json:"type"`
	Label      string `json:"label"`
	Fstype     string `json:"fstype"`
	Mountpoint string `json:"mountpoint"`
	Removable  bool   `json:"rm"`
	Hotplug    bool   `json:"hotplug"`
	Size       string `json:"size"`
	Transport  string `json:"tran"`
	Model      string `json:"model"`
}

// The external drives plugged in now, by disk path
func scan() (map[string]drive, error) {
	out, err := exec.Command("lsblk", "--json", "--list", "-o",
		"NAME,PATH,PKNAME,TYPE,LABEL,FSTYPE,MOUNTPOINT,RM,HOTPLUG,SIZE,TRAN,MODEL").Output()
	if err != nil {
		return nil, fmt.Errorf("lsblk: %w", err)
	}
	return parse(out)
}

// Groups lsblk's devices into drives. Only external disks with at least one
// filesystem count, so an empty card reader isn't a drive until a card goes in
func parse(data []byte) (map[string]drive, error) {
	var list struct {
		Devices []device `json:"blockdevices"`
	}
	if err := json.Unmarshal(data, &list); err != nil {
		return nil, fmt.Errorf("lsblk: %w", err)
	}
	byName := map[string]device{}
	for _, d := range list.Devices {
		byName[d.Name] = d
	}

	drives := map[string]drive{}
	disks := map[string]device{}
	labels := map[string]string{}
	for _, d := range list.Devices {
		disk := root(byName, d)
		if !external(disk) || d.Fstype == "" || d.Fstype == "swap" {
			continue
		}
		dr, ok := drives[disk.Path]
		if !ok {
			dr = drive{Disk: disk.Path, Size: size(disk.Size), PowerOff: disk.Hotplug}
			disks[disk.Path] = disk
		}
		dr.Filesystems = append(dr.Filesystems, filesystem{Path: d.Path, Fstype: d.Fstype, Mountpoint: d.Mountpoint})
		if labels[disk.Path] == "" {
			labels[disk.Path] = strings.TrimSpace(d.Label)
		}
		drives[disk.Path] = dr
	}
	for path, dr := range drives {
		dr.Name = name(labels[path], disks[path])
		drives[path] = dr
	}
	return drives, nil
}

// The disk a device is on: its parent's parent, and so on
func root(byName map[string]device, d device) device {
	for range 8 { // A partition in LUKS in LVM is three deep; 8 is plenty
		parent, ok := byName[d.Parent]
		if d.Parent == "" || !ok {
			break
		}
		d = parent
	}
	return d
}

// Whether a disk is one you plug in, not one inside the computer
func external(d device) bool {
	if d.Type != "disk" && d.Type != "rom" {
		return false
	}
	return d.Transport == "usb" || d.Hotplug || d.Removable || strings.HasPrefix(d.Name, "mmcblk")
}

// The drive's label, else its model, else what kind of drive it is
func name(label string, d device) string {
	if label != "" {
		return label
	}
	if model := strings.Join(strings.Fields(d.Model), " "); model != "" {
		return model
	}
	switch {
	case d.Type == "rom":
		return "Disc"
	case d.Transport == "usb":
		return "USB drive"
	case strings.HasPrefix(d.Name, "mmcblk"):
		return "SD card"
	}
	return "Drive"
}

// "29.3G" as "29.3 GB"
func size(s string) string {
	if n := len(s); n > 1 && strings.ContainsRune("KMGTP", rune(s[n-1])) {
		return s[:n-1] + " " + s[n-1:] + "B"
	}
	return s
}

// Whether udisks can mount the filesystem as it is. Encrypted and LVM and
// RAID members need unlocking or assembling first
func mountable(f filesystem) bool {
	switch f.Fstype {
	case "", "swap", "crypto_LUKS", "BitLocker", "LVM2_member", "linux_raid_member":
		return false
	}
	return true
}

// Where the drive's first mounted filesystem is, or ""
func (d drive) mountpoint() string {
	for _, f := range d.Filesystems {
		if f.Mountpoint != "" {
			return f.Mountpoint
		}
	}
	return ""
}

// Whether the drive has something locked and nothing to open
func (d drive) encrypted() bool {
	return slices.ContainsFunc(d.Filesystems, func(f filesystem) bool {
		return f.Fstype == "crypto_LUKS" || f.Fstype == "BitLocker"
	})
}

// The drives in now that weren't in before, and those gone since. A
// different drive on a reused path (unplug one stick, plug in another) is
// both gone and new
func diff(before, now map[string]drive) (added, removed []drive) {
	same := func(a, b drive) bool { return a.Name == b.Name && a.Size == b.Size }
	for path, d := range now {
		if old, ok := before[path]; !ok || !same(old, d) {
			added = append(added, d)
		}
	}
	for path, d := range before {
		if fresh, ok := now[path]; !ok || !same(d, fresh) {
			removed = append(removed, d)
		}
	}
	byDisk := func(a, b drive) int { return strings.Compare(a.Disk, b.Disk) }
	slices.SortFunc(added, byDisk)
	slices.SortFunc(removed, byDisk)
	return added, removed
}
