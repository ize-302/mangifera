package main

import (
	"reflect"
	"testing"
)

// lsblk's output with an internal NVMe disk, zram swap, an empty card
// reader, a USB disk formatted whole, a labelled USB stick with two
// partitions, an encrypted stick and a disc
const plugged = `{"blockdevices": [
 {"name":"nvme0n1","path":"/dev/nvme0n1","pkname":null,"type":"disk","label":null,"fstype":null,"mountpoint":null,"rm":false,"hotplug":false,"size":"476.9G","tran":"nvme","model":"KXG6AZNV512G TOSHIBA"},
 {"name":"nvme0n1p1","path":"/dev/nvme0n1p1","pkname":"nvme0n1","type":"part","label":null,"fstype":"vfat","mountpoint":"/boot","rm":false,"hotplug":false,"size":"1G","tran":"nvme","model":null},
 {"name":"nvme0n1p2","path":"/dev/nvme0n1p2","pkname":"nvme0n1","type":"part","label":null,"fstype":"ext4","mountpoint":"/","rm":false,"hotplug":false,"size":"475.9G","tran":"nvme","model":null},
 {"name":"zram0","path":"/dev/zram0","pkname":null,"type":"disk","label":"zram0","fstype":"swap","mountpoint":"[SWAP]","rm":false,"hotplug":false,"size":"4G","tran":null,"model":null},
 {"name":"sda","path":"/dev/sda","pkname":null,"type":"disk","label":null,"fstype":null,"mountpoint":null,"rm":true,"hotplug":false,"size":"0B","tran":"usb","model":"STORAGE DEVICE"},
 {"name":"sdb","path":"/dev/sdb","pkname":null,"type":"disk","label":null,"fstype":"ext4","mountpoint":null,"rm":false,"hotplug":true,"size":"931.5G","tran":"usb","model":"ST1000LM024   HN-M101MBB "},
 {"name":"sdc","path":"/dev/sdc","pkname":null,"type":"disk","label":null,"fstype":null,"mountpoint":null,"rm":true,"hotplug":true,"size":"28.7G","tran":"usb","model":"Ultra"},
 {"name":"sdc1","path":"/dev/sdc1","pkname":"sdc","type":"part","label":"PHOTOS","fstype":"exfat","mountpoint":"/run/media/me/PHOTOS","rm":true,"hotplug":true,"size":"20G","tran":null,"model":null},
 {"name":"sdc2","path":"/dev/sdc2","pkname":"sdc","type":"part","label":"","fstype":"vfat","mountpoint":null,"rm":true,"hotplug":true,"size":"8.7G","tran":null,"model":null},
 {"name":"sdd","path":"/dev/sdd","pkname":null,"type":"disk","label":null,"fstype":null,"mountpoint":null,"rm":true,"hotplug":true,"size":"14.5G","tran":"usb","model":null},
 {"name":"sdd1","path":"/dev/sdd1","pkname":"sdd","type":"part","label":null,"fstype":"crypto_LUKS","mountpoint":null,"rm":true,"hotplug":true,"size":"14.5G","tran":null,"model":null},
 {"name":"sr0","path":"/dev/sr0","pkname":null,"type":"rom","label":"","fstype":"iso9660","mountpoint":null,"rm":true,"hotplug":false,"size":"4.4G","tran":"sata","model":""}
]}`

func TestParse(t *testing.T) {
	got, err := parse([]byte(plugged))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]drive{
		"/dev/sdb": {Disk: "/dev/sdb", Name: "ST1000LM024 HN-M101MBB", Size: "931.5 GB", PowerOff: true,
			Filesystems: []filesystem{{Path: "/dev/sdb", Fstype: "ext4"}}},
		"/dev/sdc": {Disk: "/dev/sdc", Name: "PHOTOS", Size: "28.7 GB", PowerOff: true,
			Filesystems: []filesystem{
				{Path: "/dev/sdc1", Fstype: "exfat", Mountpoint: "/run/media/me/PHOTOS"},
				{Path: "/dev/sdc2", Fstype: "vfat"},
			}},
		"/dev/sdd": {Disk: "/dev/sdd", Name: "USB drive", Size: "14.5 GB", PowerOff: true,
			Filesystems: []filesystem{{Path: "/dev/sdd1", Fstype: "crypto_LUKS"}}},
		"/dev/sr0": {Disk: "/dev/sr0", Name: "Disc", Size: "4.4 GB",
			Filesystems: []filesystem{{Path: "/dev/sr0", Fstype: "iso9660"}}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v\nwant %+v", got, want)
	}

	if !got["/dev/sdd"].encrypted() || got["/dev/sdc"].encrypted() {
		t.Error("only sdd is encrypted")
	}
	if m := got["/dev/sdc"].mountpoint(); m != "/run/media/me/PHOTOS" {
		t.Errorf("sdc's mountpoint is %q", m)
	}
}

// A card inserted in the reader: the reader's disk gets a partition
func TestCardInserted(t *testing.T) {
	empty := `{"blockdevices": [
 {"name":"sda","path":"/dev/sda","pkname":null,"type":"disk","label":null,"fstype":null,"mountpoint":null,"rm":true,"hotplug":false,"size":"0B","tran":"usb","model":"STORAGE DEVICE"}]}`
	card := `{"blockdevices": [
 {"name":"sda","path":"/dev/sda","pkname":null,"type":"disk","label":null,"fstype":null,"mountpoint":null,"rm":true,"hotplug":false,"size":"59.5G","tran":"usb","model":"STORAGE DEVICE"},
 {"name":"sda1","path":"/dev/sda1","pkname":"sda","type":"part","label":"CAMERA","fstype":"exfat","mountpoint":null,"rm":true,"hotplug":false,"size":"59.5G","tran":null,"model":null}]}`
	before, _ := parse([]byte(empty))
	now, _ := parse([]byte(card))
	added, removed := diff(before, now)
	if len(added) != 1 || added[0].Name != "CAMERA" || added[0].PowerOff || len(removed) != 0 {
		t.Errorf("added %+v, removed %+v", added, removed)
	}
	// And taken out
	added, removed = diff(now, before)
	if len(added) != 0 || len(removed) != 1 || removed[0].Name != "CAMERA" {
		t.Errorf("added %+v, removed %+v", added, removed)
	}
}

func TestDiff(t *testing.T) {
	stick := drive{Disk: "/dev/sdb", Name: "STICK", Size: "29.3 GB"}
	other := drive{Disk: "/dev/sdb", Name: "BACKUP", Size: "1.8 TB"}
	disk := drive{Disk: "/dev/sdc", Name: "DISK", Size: "1.8 TB"}

	added, removed := diff(map[string]drive{"/dev/sdb": stick}, map[string]drive{"/dev/sdb": stick, "/dev/sdc": disk})
	if !reflect.DeepEqual(added, []drive{disk}) || removed != nil {
		t.Errorf("plugged in: added %+v, removed %+v", added, removed)
	}

	// Mounting changes a filesystem's mountpoint, not the drive
	mounted := stick
	mounted.Filesystems = []filesystem{{Path: "/dev/sdb1", Mountpoint: "/run/media/me/STICK"}}
	added, removed = diff(map[string]drive{"/dev/sdb": stick}, map[string]drive{"/dev/sdb": mounted})
	if added != nil || removed != nil {
		t.Errorf("mounted: added %+v, removed %+v", added, removed)
	}

	// Another drive on the same path
	added, removed = diff(map[string]drive{"/dev/sdb": stick}, map[string]drive{"/dev/sdb": other})
	if !reflect.DeepEqual(added, []drive{other}) || !reflect.DeepEqual(removed, []drive{stick}) {
		t.Errorf("swapped: added %+v, removed %+v", added, removed)
	}
}

func TestMountable(t *testing.T) {
	for fstype, want := range map[string]bool{
		"ext4": true, "vfat": true, "exfat": true, "ntfs": true, "iso9660": true,
		"": false, "swap": false, "crypto_LUKS": false, "LVM2_member": false,
	} {
		if got := mountable(filesystem{Fstype: fstype}); got != want {
			t.Errorf("mountable(%q) = %v", fstype, got)
		}
	}
}

func TestSize(t *testing.T) {
	for in, want := range map[string]string{"29.3G": "29.3 GB", "1.8T": "1.8 TB", "512M": "512 MB", "0B": "0B", "": ""} {
		if got := size(in); got != want {
			t.Errorf("size(%q) = %q, want %q", in, got, want)
		}
	}
}
