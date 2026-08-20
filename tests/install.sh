#!/bin/sh
#
# Install the freshly built packages and check the things a successful
# rpmbuild cannot tell you: that the dependencies resolve, that the
# scriptlets run, that the conflict actually excludes, and that the
# promotion path works.
#
# Run from the repository root with the built packages in ./out.
# Containers have no running init, so this deliberately does not try to
# start the service -- systemd-analyze verify is the closest check that
# works without PID 1.
#
# The walk mirrors a host's life: client-only first, then the refusal
# to layer the server on top, then promotion to a server.

set -eu

rpmdir=${1:-out}

fail=0
check() {
	if out=$(eval "$2" 2>&1); then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		# Without this the failure is just a name and an exit code, which
		# is not enough to fix anything from a CI log.
		printf '%s\n' "$out" | sed 's/^/         | /'
		fail=1
	fi
}

# A client host installs xymon-client and nothing else, so prove that
# stands on its own before anything else.
echo "== installing the client alone =="
# The [0-9] after the name anchors each glob to the version, so the
# debuginfo/debugsource packages can never match; only src.rpm needs
# excluding. Exactly one match each: with several builds in $rpmdir the
# quoted "$server_rpm" would reach dnf as one newline-embedded argument
# and fail the suite for the wrong reason.
client_rpm=$(find "$rpmdir" -name 'xymon-client-[0-9]*.rpm')
server_rpm=$(find "$rpmdir" -name 'xymon-[0-9]*.rpm' ! -name '*.src.rpm')
for v in client_rpm server_rpm; do
	eval "rpms=\$$v"
	[ -n "$rpms" ] || { echo "no rpm matched for $v in $rpmdir"; exit 1; }
	[ "$(printf '%s\n' "$rpms" | wc -l)" -eq 1 ] \
		|| { echo "expected exactly one rpm for $v, got:"; printf '%s\n' "$rpms"; exit 1; }
done
dnf -y install "$client_rpm"


echo "== checking the client-only install =="
check "the client installed without the server" \
	"rpm -q xymon-client && ! rpm -q xymon"

check "the xymon user exists on a client-only host" \
	"id xymon"

check "the shared unit and the role dispatcher resolve" \
	"test -f /usr/lib/systemd/system/xymonlaunch.service &&
	 test -x /usr/lib/xymon/client/bin/xymonlaunch-run &&
	 test -x /usr/lib/xymon/client/bin/xymonlaunch"

check "the dispatcher will pick the client role (no server tree)" \
	"test ! -x /usr/lib/xymon/server/bin/xymond"

check "the client role drop-in is installed, the server one is not" \
	"test -f /usr/lib/systemd/system/xymonlaunch.service.d/client.conf &&
	 ! test -e /usr/lib/systemd/system/xymonlaunch.service.d/server.conf"

# Without net-tools the ifstat/ports/route client sections arrive empty,
# and nothing errors -- the data is just missing on the server.
check "net-tools arrived with the client" \
	"command -v netstat && command -v ifconfig"

# An upgrade must not reset the server address a user configured.
check "the client configs are marked config" \
	"rpm -qc xymon-client | grep -qx /etc/xymon-client/xymonclient.cfg"

check "systemd accepts the shared unit" \
	"systemd-analyze verify --man=no /usr/lib/systemd/system/xymonlaunch.service"

check "log rotation ships with the client" \
	"test -f /etc/logrotate.d/xymon"

# The design's core promise: a host is one role or the other, and dnf
# says so instead of silently layering the server on top.
echo "== the server must refuse to install over the client =="
# Fail AND say why: an unrelated dnf error (bad rpm, missing dep) must
# not pass as the conflict working.
# Match the specific conflict, not any message containing "conflict":
# libdnf prefixes generic resolution failures with "conflicting
# requests", so a broken Requires would otherwise pass as the design
# working.
check "dnf install xymon fails on the package conflict" \
	"if dnf -y install $server_rpm >/tmp/conflict.out 2>&1; then false;
	 else grep -q 'conflicts with' /tmp/conflict.out &&
	      grep -q 'xymon-client' /tmp/conflict.out; fi"

# Promotion is one transaction: the server (which embeds the client
# tree) replaces the standalone client. --allowerasing is the
# local-file equivalent of 'dnf swap xymon-client xymon'.
echo "== promoting the host to a server =="
dnf -y install --allowerasing "$server_rpm"

check "the swap left the server and removed the client package" \
	"rpm -q xymon && ! rpm -q xymon-client"

check "the client tree survived the swap (now embedded)" \
	"test -x /usr/lib/xymon/client/bin/xymonlaunch &&
	 test -x /usr/lib/xymon/client/bin/xymonlaunch-run &&
	 test -f /etc/xymon-client/clientlaunch.cfg"

check "the dispatcher now picks the server role" \
	"test -x /usr/lib/xymon/server/bin/xymond"

check "the drop-ins swapped roles with the packages" \
	"test -f /usr/lib/systemd/system/xymonlaunch.service.d/server.conf &&
	 ! test -e /usr/lib/systemd/system/xymonlaunch.service.d/client.conf"

# The dispatcher must refuse rather than silently run the client role
# when the server marker is present but the server tree is not usable
# -- a broken install that would otherwise look healthy while the whole
# fleet goes unmonitored.
check "the dispatcher fails loudly on a broken server install" \
	"chmod a-x /usr/lib/xymon/server/bin/xymond &&
	 ! /usr/lib/xymon/client/bin/xymonlaunch-run --help >/dev/null 2>&1;
	 rc=\$?; chmod 0755 /usr/lib/xymon/server/bin/xymond; test \$rc -eq 0"

check "the embedded client configs are still marked config" \
	"rpm -qc xymon | grep -qx /etc/xymon-client/xymonclient.cfg"

echo "== installing the remaining subpackages =="
# Actually the remaining ones: the server and client rpms are excluded
# (installed above / conflicting), leaving client-local, devel, tools.
set -- $(find "$rpmdir" -name '*.rpm' \
	! -name 'xymon-[0-9]*' ! -name 'xymon-client-[0-9]*' \
	! -name '*debuginfo*' ! -name '*debugsource*' ! -name '*.src.rpm')
[ "$#" -gt 0 ] || { echo "no packages found in $rpmdir"; exit 1; }
dnf -y install "$@"

echo "== checking the server host =="
check "all server-side packages are installed" \
	"rpm -q xymon xymon-client-local xymon-devel xymon-tools"

# The devel package is only useful if the relative includes still resolve,
# so compile against it rather than merely checking the files exist.
check "a module can be compiled against xymon-devel" \
	"printf '#include \"libxymon.h\"\\nint main(void){return 0;}\\n' > /tmp/t.c &&
	 cc -I/usr/include/xymon/include -c /tmp/t.c -o /tmp/t.o"

# %pre creates the account; if shadow-utils were missing from Requires(pre)
# the scriptlet would have failed silently on a minimal image.
check "the xymon user exists" \
	"id xymon"

check "server config is installed" \
	"test -f /etc/xymon/xymonserver.cfg"

check "apache drop-in is installed" \
	"test -f /etc/httpd/conf.d/xymon-apache.conf"

check "unit file is installed" \
	"test -f /usr/lib/systemd/system/xymonlaunch.service"

check "tmpfiles config is installed" \
	"test -f /usr/lib/tmpfiles.d/xymon.conf"

# The $PATH conveniences (nothing at runtime uses them -- the
# dispatcher execs the server tree directly), so a wrong symlink target
# in %install shows up here rather than under an admin's fingers.
check "/usr/bin/xymoncmd resolves" \
	"test -x /usr/bin/xymoncmd"
check "/usr/sbin/xymonlaunch resolves" \
	"test -x /usr/sbin/xymonlaunch"

# This is the packaging-side answer to the build-host-hostname problem:
# the build bakes "localhost" and %post rewrites it. If the scriptlet ever
# stops firing, every installation would silently report as "localhost".
check "%post rewrote XYMONSERVERHOSTNAME away from localhost" \
	"grep -q '^XYMONSERVERHOSTNAME=' /etc/xymon/xymonserver.cfg && \
	 ! grep -q '^XYMONSERVERHOSTNAME=\"localhost\"' /etc/xymon/xymonserver.cfg"

# The shipped apache config points AuthUserFile here; if the file is
# missing every /xymon-seccgi request is a 500, and if it is not
# apache-owned the critical-editor CGI cannot save.
check "the web auth files exist and are apache-owned" \
	"stat -c '%U:%G' /etc/xymon/xymonpasswd | grep -qx apache:apache &&
	 stat -c '%U:%G' /etc/xymon/xymongroups | grep -qx apache:apache"

check "critical.cfg is writable by the web CGIs" \
	"stat -c '%U' /etc/xymon/critical.cfg | grep -qx apache"

check "xymond_client ships for local analysis" \
	"test -x /usr/lib/xymon/server/bin/xymond_client"

check "the diagnostic tools are executable" \
	"test -x /usr/lib/xymon/server/bin/stackio -a -x /usr/lib/xymon/server/bin/loadhosts"

check "the static library is packaged" \
	"ls /usr/lib*/xymon/libxymon.a"

check "manual pages are packaged" \
	"rpm -ql xymon | grep -q '/share/man/'"

# Catches unit syntax errors and, importantly, an ExecStart that points at
# something not in the package. --man=no because verify otherwise shells
# out to man(1) for every Documentation= entry, which a minimal container
# does not have installed -- that is an image property, not a unit defect.
check "systemd accepts the unit on the server host" \
	"systemd-analyze verify --man=no /usr/lib/systemd/system/xymonlaunch.service"

echo "== hostname now configured as =="
grep '^XYMONSERVERHOSTNAME=' /etc/xymon/xymonserver.cfg || :

echo "== manual pages shipped =="
for sec in 1 5 7 8; do
	printf '   man%s: %s pages\n' "$sec" \
		"$(rpm -ql xymon | grep -c "/share/man/man$sec/")"
done
echo "   man7 contents: $(rpm -ql xymon | grep '/share/man/man7/' | tr '\n' ' ')"

# The reverse swap: the server host becomes a client again. Exercises
# the server package's %preun guard (the shared unit must survive the
# erase) and rpm's install-before-erase ordering over the shared paths.
echo "== demoting the host back to a client =="
dnf -y install --allowerasing "$client_rpm"

check "the demotion left the client and removed the server" \
	"rpm -q xymon-client && ! rpm -q xymon"

check "the dispatcher picks the client role again" \
	"test ! -x /usr/lib/xymon/server/bin/xymond &&
	 test -x /usr/lib/xymon/client/bin/xymonlaunch-run"

check "the shared unit survived and the drop-ins swapped back" \
	"test -f /usr/lib/systemd/system/xymonlaunch.service &&
	 test -f /usr/lib/systemd/system/xymonlaunch.service.d/client.conf &&
	 ! test -e /usr/lib/systemd/system/xymonlaunch.service.d/server.conf"

check "client-local survived the demotion (its rich dependency held)" \
	"rpm -q xymon-client-local"

exit "$fail"
