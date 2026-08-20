#!/bin/sh
#
# Assertions about the built packages themselves -- read from the rpms,
# nothing installed, no systemd needed. This is the cheap half of the
# safety net: the two roles' packages share a unit and a whole file
# tree, and a divergence between them is invisible to rpmbuild.
#
# The expensive half is tests/systemd.sh, which needs a live PID 1.
#
# Run from the repository root with the built packages in ./out. Needs
# rpm and rpm2cpio, so it runs inside a distro container, not on the
# workstation.
#
# Every comparison here asserts its inputs are non-empty first: two
# empty file lists diff clean, and the sha256 of nothing equals the
# sha256 of nothing, so a missing tool or a moved path would otherwise
# read as a pass.

set -eu

rpmdir=${1:-out}

# cmp and diff come from diffutils, which a minimal image does not
# have. Checked up front so a missing tool is one clear error rather
# than a scatter of confusing failures.
for t in rpm rpm2cpio cpio cmp diff; do
	command -v "$t" >/dev/null 2>&1 || {
		echo "missing $t -- needs rpm, cpio and diffutils, inside a distro container" >&2
		exit 1
	}
done

fail=0
check() {
	if out=$(eval "$2" 2>&1); then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		printf '%s\n' "$out" | sed 's/^/         | /'
		fail=1
	fi
}

# One rpm per pattern: several builds in ./out would make every
# assertion below read whichever the filesystem returned first.
one_rpm() {
	found=$(find "$rpmdir" -name "$1" ! -name '*.src.rpm')
	[ -n "$found" ] || { echo "no rpm matched $1 in $rpmdir" >&2; return 1; }
	[ "$(printf '%s\n' "$found" | wc -l)" -eq 1 ] \
		|| { echo "expected one rpm for $1, got:" >&2; printf '%s\n' "$found" >&2; return 1; }
	printf '%s\n' "$found"
}

server=$(one_rpm 'xymon-[0-9]*.rpm') || exit 1
client=$(one_rpm 'xymon-client-[0-9]*.rpm') || exit 1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Unpack both payloads once, so the content assertions below read real
# files: a path that moved becomes a missing file (a failure), not an
# empty pipe that greps as absent.
for role in server client; do
	eval "rpmfile=\$$role"
	mkdir -p "$work/$role"
	(cd "$work/$role" && rpm2cpio "$rpmfile" | cpio -idm --quiet)
done

unit=usr/lib/systemd/system/xymonlaunch.service
serverconf=usr/lib/systemd/system/xymonlaunch.service.d/server.conf
clientconf=usr/lib/systemd/system/xymonlaunch.service.d/client.conf
dispatcher=usr/lib/xymon/client/bin/xymonlaunch-run

echo "== the exclusion is stated in metadata =="

# The design's core promise. Without this tag the packages silently
# co-install and both roles' launchers fight over the same host.
check "xymon declares Conflicts: xymon-client" \
	"rpm -qp --conflicts $server | grep -qx 'xymon-client'"

check "xymon does not require xymon-client (the client is embedded)" \
	"! rpm -qp --requires $server | grep -q '^xymon-client'"

echo "== one unit name, one dispatcher, both packages =="

# Both roles must present the same service name, and the unit and
# dispatcher must be identical in both packages -- they are the same
# files from one build, and a divergence would mean a host behaves
# differently depending on which package delivered it.
for role in server client; do
	check "the $role package ships xymonlaunch.service" \
		"test -s $work/$role/$unit"
	check "the $role package ships the role dispatcher" \
		"test -s $work/$role/$dispatcher && test -x $work/$role/$dispatcher"
	check "the $role package ships no xymon-client.service" \
		"! test -e $work/$role/usr/lib/systemd/system/xymon-client.service"
done

check "the unit is byte-identical in both packages" \
	"cmp $work/server/$unit $work/client/$unit"

check "the dispatcher is byte-identical in both packages" \
	"cmp $work/server/$dispatcher $work/client/$dispatcher"

echo "== the per-role drop-ins =="

# Each role's package owns exactly its own drop-in. These files are also
# the markers the %preun swap guards test, so a package shipping the
# wrong one would make a guard permanently true or permanently false.
check "the server package owns only server.conf" \
	"test -s $work/server/$serverconf && ! test -e $work/server/$clientconf"

check "the client package owns only client.conf" \
	"test -s $work/client/$clientconf && ! test -e $work/client/$serverconf"

# What each drop-in exists to do. The base unit carries the client's
# semantics, so these assertions are what keep the server's checkpoint
# protection and the client's boot-time network wait from being
# silently dropped into (or out of) the shared unit.
check "server.conf protects xymond's children on stop" \
	"grep -q '^KillMode=process' $work/server/$serverconf &&
	 grep -q '^SendSIGKILL=no' $work/server/$serverconf"

check "client.conf waits for the network" \
	"grep -q '^Wants=network-online.target' $work/client/$clientconf &&
	 grep -q '^After=network-online.target' $work/client/$clientconf"

# The server is a listening daemon whose tasks retry; making it wait for
# wait-online delays monitoring by up to minutes on every boot.
check "the base unit does not wait for the network" \
	"! grep -q 'network-online' $work/server/$unit"

# Default cgroup kill in the base unit is what stops a wedged client
# from running alongside its replacement; the server overrides it.
check "the base unit keeps the client's cgroup kill" \
	"! grep -qE '^(KillMode|SendSIGKILL)=' $work/server/$unit"

echo "== enablement policy =="

# A fresh client must not start unconfigured: its baked-in XYMSRV is
# 127.0.0.1, so an auto-enabled client reports into the void and fills
# logs. Only the server carries the enable preset.
check "only the server package ships the enable preset" \
	"ls $work/server/usr/lib/systemd/system-preset/*xymonlaunch* >/dev/null 2>&1 &&
	 ! ls $work/client/usr/lib/systemd/system-preset/ >/dev/null 2>&1"

echo "== the shared client tree is identical in both packages =="

# The two packages ship the same client tree from the same build. If the
# %files entries drift -- a config that is %config(noreplace) in one
# role and not the other, or different permissions -- an upgrade would
# silently reset an admin's edits on one kind of host only. rpmbuild
# cannot see this; comparing the two manifests can.
check "both packages list the same client tree files" \
	"rpm -qlp $server | grep '^/usr/lib/xymon/client/' | sort > $work/s.files &&
	 rpm -qlp $client | grep '^/usr/lib/xymon/client/' | sort > $work/c.files &&
	 test -s $work/s.files && diff $work/s.files $work/c.files"

check "both packages mark the same client configs %config(noreplace)" \
	"rpm -qcp $server | grep '^/usr/lib/xymon/client/' | sort > $work/s.conf &&
	 rpm -qcp $client | grep '^/usr/lib/xymon/client/' | sort > $work/c.conf &&
	 test -s $work/s.conf && diff $work/s.conf $work/c.conf"

check "the client tree has identical modes and ownership in both" \
	"rpm -qp --qf '[%{FILENAMES} %{FILEMODES:octal} %{FILEUSERNAME} %{FILEGROUPNAME}\n]' $server |
	   grep '^/usr/lib/xymon/client/' | sort > $work/s.attr &&
	 rpm -qp --qf '[%{FILENAMES} %{FILEMODES:octal} %{FILEUSERNAME} %{FILEGROUPNAME}\n]' $client |
	   grep '^/usr/lib/xymon/client/' | sort > $work/c.attr &&
	 test -s $work/s.attr && diff $work/s.attr $work/c.attr"

check "logrotate ships with both roles, editable in both" \
	"rpm -qcp $server | grep -qx '/etc/logrotate.d/xymon' &&
	 rpm -qcp $client | grep -qx '/etc/logrotate.d/xymon'"

echo "== the swap guards reference files that exist =="

# The %preun guards decide whether a swap is in progress by probing the
# other role's drop-in. If a rename ever left a guard pointing at a path
# no package ships, the guard would be silently always-true and the swap
# would disable the shared unit on the promoted host.
check "the server's scriptlets probe a path the client package ships" \
	"rpm -qp --scripts $server | grep -q '$clientconf' && test -s $work/client/$clientconf"

check "the client's scriptlets probe a path the server package ships" \
	"rpm -qp --scripts $client | grep -q '$serverconf' && test -s $work/server/$serverconf"

check "the dispatcher keys off the same marker as the scriptlets" \
	"grep -q '$serverconf' $work/server/$dispatcher"

echo "== both roles can stand up the account alone =="

# With no dependency between the packages, whichever is installed must
# create the xymon user itself.
for role in server client; do
	eval "rpmfile=\$$role"
	check "the $role package creates the xymon account in %pre" \
		"rpm -qp --scripts $rpmfile | grep -qE 'sysusers|useradd'"
done

exit "$fail"
