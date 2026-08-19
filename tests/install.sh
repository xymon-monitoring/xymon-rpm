#!/bin/sh
#
# Install the freshly built packages and check the things a successful
# rpmbuild cannot tell you: that the dependencies resolve, that the
# scriptlets run, and that the unit file points at binaries that exist.
#
# Run from the repository root with the built packages in ./out.
# Containers have no running init, so this deliberately does not try to
# start the service -- systemd-analyze verify is the closest check that
# works without PID 1.

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
# stands on its own before the rest is layered on top -- installed
# together, the server package masks everything the client is missing.
echo "== installing the client alone =="
client_rpm=$(find "$rpmdir" -name 'xymon-client-[0-9]*.rpm' ! -name '*debuginfo*')
[ -n "$client_rpm" ] || { echo "no xymon-client package in $rpmdir"; exit 1; }
dnf -y install "$client_rpm"

echo "== checking the client-only install =="
check "the client installed without the server" \
	"rpm -q xymon-client && ! rpm -q xymon"

check "the xymon user exists on a client-only host" \
	"id xymon"

check "the client unit and its launcher resolve" \
	"test -f /usr/lib/systemd/system/xymon-client.service &&
	 test -x /usr/lib/xymon/client/bin/xymonclient-run &&
	 test -x /usr/lib/xymon/client/bin/xymonlaunch"

# Without net-tools the ifstat/ports/route client sections arrive empty,
# and nothing errors -- the data is just missing on the server.
check "net-tools arrived with the client" \
	"command -v netstat && command -v ifconfig"

# An upgrade must not reset the server address a user configured.
check "the client configs are marked config" \
	"rpm -qc xymon-client | grep -q client/etc/xymonclient.cfg"

check "systemd accepts the client unit" \
	"systemd-analyze verify --man=no /usr/lib/systemd/system/xymon-client.service"

check "log rotation ships with the client" \
	"test -f /etc/logrotate.d/xymon"

echo "== installing everything =="
# Skip debuginfo/debugsource: they add nothing here and drag in sources.
set -- $(find "$rpmdir" -name '*.rpm' \
	! -name '*debuginfo*' ! -name '*debugsource*' ! -name '*.src.rpm')
[ "$#" -gt 0 ] || { echo "no packages found in $rpmdir"; exit 1; }
dnf -y install "$@"

echo "== checking =="
check "all packages are installed" \
	"rpm -q xymon xymon-client xymon-client-local xymon-devel xymon-tools"

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

# The unit invokes these by absolute path, so a wrong symlink target in
# %install shows up here rather than at first boot on a user's machine.
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

# Ask the package rather than probing a path: the section, the name and the
# compression suffix all vary (EL uses gzip, Fedora zstd).
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
check "systemd accepts the unit" \
	"systemd-analyze verify --man=no /usr/lib/systemd/system/xymonlaunch.service"

echo "== hostname now configured as =="
grep '^XYMONSERVERHOSTNAME=' /etc/xymon/xymonserver.cfg || :

echo "== manual pages shipped =="
for sec in 1 5 7 8; do
	printf '   man%s: %s pages\n' "$sec" \
		"$(rpm -ql xymon | grep -c "/share/man/man$sec/")"
done
echo "   man7 contents: $(rpm -ql xymon | grep '/share/man/man7/' | tr '\n' ' ')"

exit "$fail"
