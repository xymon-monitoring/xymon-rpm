#!/bin/sh
#
# Does the thing actually monitor? Every other suite here tests
# packaging -- files, units, scriptlets, upgrades -- and would stay green
# if the daemons never spoke to each other. This one installs the server,
# has the client report into it, and asserts the data arrives and is
# readable back out.
#
# The point is the negative control: the board is checked *before* the
# client runs and must be empty, so a query that always returns something
# cannot pass. Without that, every assertion below could be satisfied by
# a server that ignores its input.
#
# No systemd needed -- xymonlaunch runs in the foreground under the same
# dispatcher the unit uses, which is also a check that the dispatcher
# picks the server role from the drop-in alone.
#
# STATUS: this suite FAILS on the current packaging, and that failure is
# the finding rather than a bug in the test. Measured on the real path
# -- the server's own tasks.cfg client -- in a single run:
#
#   t=300s  clientdata=15677B  columns: clientlog conn info trends
#                                       xymond xymongen xymonnet
#
# The client half works. It builds a 15,677-byte report with all 17
# sections, xymond receives and stores it, and `clientlog <host>` returns
# it in full. What never happens is the analysis: no cpu, disk, memory or
# procs column ever appears. xymond_client is running, its binary is in
# the xymon package, analysis.cfg is installed. clientdata.log holds one
# line, "Peer not up, flushing message queue", from startup.
#
# Ruled out by measurement: exporting XYMONCLIENTHOME from the dispatcher
# changes nothing. (It does fix a different failure -- running the client
# by hand via `xymoncmd --env=...` leaves XYMONCLIENTHOME empty so it
# searches /bin -- but that is not the real path and not this bug.)
#
# Deliberately NOT wired into .github/workflows/build.yml: it would stop
# publishing, and the packaging's other properties are worth continuing
# to ship while this is understood. Wire it in once it passes.
#
# Needs procps-ng for pgrep. Run from the repository root with the built
# packages in ./out.

set -eu

rpmdir=${1:-out}
fail=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		fail=1
	fi
}

# Wait for a condition rather than sleeping a guessed interval: the
# client's first report lands when xymonlaunch decides, not on our clock.
wait_for() {
	timeout=$1; shift
	while [ "$timeout" -gt 0 ]; do
		eval "$@" >/dev/null 2>&1 && return 0
		timeout=$((timeout - 1))
		sleep 1
	done
	return 1
}

command -v pkill >/dev/null 2>&1 ||
	{ echo "NOT OK   pkill is missing (procps-ng)"; exit 1; }

server=$(find "$rpmdir" -name 'xymon-4*.rpm' ! -name '*debug*' ! -name '*.src.rpm' | head -1)
[ -n "$server" ] || { echo "NOT OK   no server rpm in $rpmdir"; exit 1; }

dnf -y install "$server" >/dev/null 2>&1 ||
	{ echo "NOT OK   the server package did not install"; exit 1; }

CH=/usr/lib/xymon/client
SH=/usr/lib/xymon/server
host=$(uname -n)

# A client reporting a name the server does not know is a "ghost" and is
# dropped, so register it the way an administrator would.
grep -q "$host" /etc/xymon/hosts.cfg 2>/dev/null ||
	echo "127.0.0.1 $host # conn" >> /etc/xymon/hosts.cfg

echo "== the server comes up =="
"$CH/bin/xymonlaunch-run" >/tmp/launch.log 2>&1 &
launch_pid=$!
check "the dispatcher stayed in the foreground" "kill -0 $launch_pid"
check "it selected the server role" \
	"tr '\\0' ' ' < /proc/$launch_pid/cmdline | grep -q '/server/bin/xymonlaunch'"
check "xymond is listening on 1984" \
	"wait_for 30 \"grep -q ':07C0' /proc/net/tcp /proc/net/tcp6\""

# THE NEGATIVE CONTROL. If this reports data before any client has run,
# every assertion below is meaningless.
board_before=$("$SH/bin/xymon" 127.0.0.1 "xymondboard host=$host" 2>/dev/null || true)
check "the board is empty before the client reports (control)" \
	"test -z \"$board_before\""

echo "== the client reports into it =="
# The analysis worker has to be up before the data arrives: xymond_channel
# logs "Peer not up, flushing message queue" and drops the report
# otherwise, which looks exactly like a server that cannot parse it.
check "the analysis worker started" \
	"wait_for 60 'pgrep -f xymond_client >/dev/null'"

# --env explicitly: on a server host xymoncmd finds xymonserver.cfg
# first (common/xymoncmd.c:145) and would hand the client the server's
# XYMONHOME, sending it looking for client binaries in server/bin. The
# server's own tasks.cfg passes an ENVFILE for the same reason.
run_client() {
	"$CH/bin/xymoncmd" --env="$CH/etc/xymonclient.cfg" \
		"$CH/bin/xymonclient.sh" >/tmp/client.log 2>&1 || true
}
run_client
check "the client found the programs it runs" \
	"! grep -q 'No such file' /tmp/client.log"
check "the server accepted a report for this host" \
	"wait_for 30 \"$SH/bin/xymon 127.0.0.1 'xymondboard host=$host' | grep -q .\""

# Report again until the parsed columns appear rather than assuming the
# first one was processed: a report that races the worker is dropped, and
# retrying is what a real client does every five minutes anyway.
tries=0
while [ $tries -lt 6 ]; do
	"$SH/bin/xymon" 127.0.0.1 "xymondboard host=$host" 2>/dev/null |
		grep -q '|cpu|' && break
	sleep 10
	run_client
	tries=$((tries + 1))
done

board=$("$SH/bin/xymon" 127.0.0.1 "xymondboard host=$host" 2>/dev/null || true)
echo "== and the data is real =="
for col in cpu disk memory procs; do
	check "the $col status arrived" "echo '$board' | grep -q '|$col|'"
done
check "the status has a colour, not just a name" \
	"echo '$board' | grep -qE '\\|(green|yellow|red|clear)\\|'"

# hostdata is what the server writes to disk; a board entry that never
# reaches storage would leave nothing behind after a restart.
check "the server stored the client's data on disk" \
	"wait_for 20 \"find /var/lib/xymon/hostdata -name '$host*' | grep -q .\""

kill "$launch_pid" 2>/dev/null || :
pkill -f 'server/bin/xymonlaunch' 2>/dev/null || :

[ "$fail" = 0 ] && echo "monitoring tests passed" || echo "monitoring tests FAILED"
exit "$fail"
