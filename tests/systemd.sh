#!/bin/sh
#
# The lifecycle test: what the packages do to systemd's state as a host
# changes role. This is the half tests/install.sh structurally cannot
# reach -- it runs without PID 1, where every systemctl call in a
# scriptlet is swallowed by `|| :` and the scriptlets "pass" by doing
# nothing.
#
# Everything asserted here is a bug this packaging has actually had:
# enablement lost across a swap, a deliberately disabled unit silently
# re-enabled by the departing package's preset, a fresh client
# auto-started against an unconfigured server address, the wrong role's
# kill semantics applied to a running process.
#
# MUST run inside a container with systemd as PID 1 (see the
# systemd-lifecycle job in .github/workflows/build.yml):
#
#     docker run -d --privileged --cgroupns=host \
#         -v /sys/fs/cgroup:/sys/fs/cgroup:rw <image> /sbin/init
#
# Run from the repository root with the built packages in ./out.

set -eu

rpmdir=${1:-out}

# Never let this file pass by accident: without a live systemd every
# assertion below would be vacuous, which is exactly the failure mode
# it exists to close.
# /proc, not ps(1): a minimal image has no procps, and a missing tool
# must not be mistaken for a missing init.
if [ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]; then
	echo "PID 1 is not systemd -- this test needs a systemd container" >&2
	exit 1
fi
systemctl is-system-running >/dev/null 2>&1 || \
	systemctl is-system-running 2>&1 | grep -qE 'running|degraded' || {
		echo "systemd is not up inside this container" >&2
		exit 1
	}

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

one_rpm() {
	found=$(find "$rpmdir" -name "$1" ! -name '*.src.rpm')
	[ -n "$found" ] || { echo "no rpm matched $1 in $rpmdir" >&2; return 1; }
	[ "$(printf '%s\n' "$found" | wc -l)" -eq 1 ] \
		|| { echo "expected one rpm for $1, got:" >&2; printf '%s\n' "$found" >&2; return 1; }
	printf '%s\n' "$found"
}

server=$(one_rpm 'xymon-[0-9]*.rpm') || exit 1
client=$(one_rpm 'xymon-client-[0-9]*.rpm') || exit 1

unit=xymonlaunch.service

# Which role is running, read from the unit's own main process: the
# dispatcher execs the server tree's launcher for a server and the
# client tree's for a client, so the binary path is the answer.
#
# Deliberately NOT pgrep: a match on "xymonlaunch" or a config name
# anywhere in any process's command line -- a wrapper script, an editor,
# this test's own shell -- would answer for the wrong process. Scoping
# to MainPID keeps the question about the service.
role_of() {
	pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null || echo 0)
	case "$pid" in ''|0) echo none; return ;; esac
	cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo)
	case "$cmd" in
	*/server/bin/xymonlaunch*) echo server ;;
	*/client/bin/xymonlaunch*) echo client ;;
	*)                         echo "unknown:$cmd" ;;
	esac
}

echo "== a fresh client must not start itself =="
dnf -y install "$client" >/dev/null

# The client's baked-in XYMSRV is 127.0.0.1: a client that enables
# itself on install reports into the void and fills logs.
check "installing the client does not enable the unit" \
	"! systemctl is-enabled --quiet $unit"
check "installing the client does not start the unit" \
	"! systemctl is-active --quiet $unit"

echo "== the client role runs =="
systemctl enable --now "$unit" >/dev/null 2>&1 || :
sleep 3

check "the unit is active in the client role" \
	"systemctl is-active --quiet $unit && test \"\$(role_of)\" = client"

# Proves the drop-in mechanism is live, not just installed: the base
# unit's cgroup kill must be in effect for a client.
check "the client role uses the default cgroup kill" \
	"systemctl show -p KillMode --value $unit | grep -qx 'control-group'"

client_pid=$(systemctl show -p MainPID --value "$unit")

echo "== promotion: dnf swap xymon-client xymon =="
dnf -y install --allowerasing "$server" >/dev/null

# The swap must stop the old role -- while its own drop-in still
# applies -- and must leave enablement alone, so the documented
# restart brings the new role up on a host that still starts at boot.
check "the promotion stopped the old client process" \
	"! kill -0 $client_pid 2>/dev/null"
check "the unit stayed enabled across the promotion" \
	"systemctl is-enabled --quiet $unit"

systemctl restart "$unit" >/dev/null 2>&1 || :
sleep 3

check "the unit is active in the server role after the restart" \
	"systemctl is-active --quiet $unit && test \"\$(role_of)\" = server"

# The server's drop-in must now be the one in effect: this is what
# keeps xymond's children alive through a stop so they can finish
# checkpoints.
check "the server role protects xymond's children on stop" \
	"systemctl show -p KillMode --value $unit | grep -qx 'process'"

echo "== a deliberately disabled unit must stay disabled across a swap =="
systemctl disable --now "$unit" >/dev/null 2>&1 || :

# The departing package's preset ("enable xymonlaunch.service") is
# still on disk during the swap; a preset run here would silently
# re-enable monitoring an admin had turned off.
dnf -y install --allowerasing "$client" >/dev/null
check "the demotion did not re-enable the disabled unit" \
	"! systemctl is-enabled --quiet $unit"
check "the demotion did not start the disabled unit" \
	"! systemctl is-active --quiet $unit"

echo "== demotion of a running server =="
dnf -y install --allowerasing "$server" >/dev/null
systemctl enable --now "$unit" >/dev/null 2>&1 || :
sleep 3
server_pid=$(systemctl show -p MainPID --value "$unit")
check "the server role is running again" \
	"systemctl is-active --quiet $unit && test \"\$(role_of)\" = server"

dnf -y install --allowerasing "$client" >/dev/null

check "the demotion stopped the old server process" \
	"! kill -0 $server_pid 2>/dev/null"
check "the unit stayed enabled across the demotion" \
	"systemctl is-enabled --quiet $unit"

systemctl restart "$unit" >/dev/null 2>&1 || :
sleep 3

check "the unit is active in the client role after the restart" \
	"systemctl is-active --quiet $unit && test \"\$(role_of)\" = client"
check "the client's kill semantics are back" \
	"systemctl show -p KillMode --value $unit | grep -qx 'control-group'"

echo "== plain removal still tears down =="
# The guards must only spare the unit during a swap: an ordinary
# removal has to disable and stop it, or the host boots into a failed
# unit forever.
dnf -y remove xymon-client >/dev/null
check "removing the last package stopped the unit" \
	"! systemctl is-active --quiet $unit"
check "removing the last package left no enablement behind" \
	"! systemctl is-enabled $unit 2>/dev/null | grep -q enabled"

exit "$fail"
