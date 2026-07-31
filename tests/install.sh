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

echo "== installing =="
# Skip debuginfo/debugsource: they add nothing here and drag in sources.
set -- $(find "$rpmdir" -name '*.rpm' \
	! -name '*debuginfo*' ! -name '*debugsource*' ! -name '*.src.rpm')
[ "$#" -gt 0 ] || { echo "no packages found in $rpmdir"; exit 1; }
dnf -y install "$@"

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

echo "== checking =="
check "both packages are installed" \
	"rpm -q xymon xymon-client"

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

# Ask the package rather than probing a path: the section, the name and the
# compression suffix all vary (EL uses gzip, Fedora zstd).
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
