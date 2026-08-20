#!/bin/sh
#
# Install the currently PUBLISHED build, seed it with the state an
# administrator creates, upgrade to the freshly built packages, and
# prove the transaction succeeds with nothing lost.
#
# The only test that exercises %pretrans. It exists because every layout
# move here has had to clear a directory out of the way for a symlink,
# which rpm refuses to do and which fails the whole transaction. Testing
# that by hand found two defects no other suite could see: a failed
# upgrade, and a migration that deleted the admin's files while moving
# them.
#
# The fixture is the published snapshot channel, so this is exactly the
# step a following user takes. Run from the repository root with the
# packages in ./out. Needs network access to the published repository.

set -eu

rpmdir=${1:-out}
rpmdir=$(cd "$rpmdir" 2>/dev/null && pwd) || {
	echo "no such directory: ${1:-out}" >&2
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

new_server=$(find "$rpmdir" -name 'xymon-[0-9]*.rpm' ! -name '*.src.rpm')
[ "$(printf '%s\n' "$new_server" | wc -l)" -eq 1 ] || {
	echo "expected exactly one xymon rpm in $rpmdir, got:" >&2
	printf '%s\n' "$new_server" >&2
	exit 1
}

echo "== fetching the published build =="
curl -fsS -o /etc/yum.repos.d/xymon.repo \
	https://xymon-monitoring.github.io/xymon-rpm/xymon.repo
opts="--disablerepo=xymon --enablerepo=xymon-snapshot --nogpgcheck"

# A target with nothing published yet (a newly added release) has no
# fixture to upgrade from. Say so loudly rather than passing quietly.
if ! dnf -y $opts install xymon >/dev/null 2>&1; then
	echo "SKIP     nothing published for this release yet -- no fixture to upgrade from"
	exit 0
fi
echo "         published: $(rpm -q --qf '%{version}-%{release}' xymon)"
echo "         building:  $(rpm -qp --qf '%{version}-%{release}' "$new_server" 2>/dev/null)"

echo "== seeding the state an admin would have =="

# Paths written the upstream way, so this works whichever layout the
# published build has: in the old one they are real directories, in the
# new one symlinks to the same content.
sed -i 's/^XYMSRV=.*/XYMSRV="192.0.2.50"/' \
	/usr/lib/xymon/client/etc/xymonclient.cfg
printf '\n[mycheck]\n\tCMD /bin/true\n' >> /usr/lib/xymon/client/etc/clientlaunch.cfg
touch /var/lib/xymon/www/gifs/mine.gif
mkdir -p /var/lib/xymon/www/help/mydocs
echo 'local note' > /var/lib/xymon/www/help/mydocs/note.txt
echo "         XYMSRV edited, a task added, a gif and a help subdir dropped in"

echo "== upgrading to the build under test =="
set -- $(find "$rpmdir" -name '*.rpm' \
	! -name 'xymon-client-[0-9]*' \
	! -name '*debuginfo*' ! -name '*debugsource*' ! -name '*.src.rpm')
if ! upgrade_out=$(dnf -y $opts upgrade "$@" 2>&1); then
	echo "NOT OK   the upgrade transaction failed"
	printf '%s\n' "$upgrade_out" | grep -iE 'error|conflict' | sed 's/^/         | /'
	exit 1
fi
echo "ok       the upgrade transaction succeeded"

# rpm reports a file conflict as an error, but a scriptlet that failed
# is only a warning -- and a %pretrans that did not run is exactly how
# a migration silently does nothing.
check "no scriptlet failed during the upgrade" \
	"! printf '%s' \"\$upgrade_out\" | grep -qiE 'scriptlet failed|warning:.*scriptlet'"

check "the new build is what is installed now" \
	"test \"\$(rpm -q --qf '%{version}-%{release}' xymon)\" = \
	      \"\$(rpm -qp --qf '%{version}-%{release}' $new_server)\""

echo "== what the admin left behind must still be there =="

check "the edited XYMSRV survived" \
	"grep -q '^XYMSRV=\"192.0.2.50\"' /etc/xymon-client/xymonclient.cfg"

check "the added task survived" \
	"grep -q '^\[mycheck\]' /etc/xymon-client/clientlaunch.cfg"

check "the custom gif survived" \
	"test -f /usr/share/xymon/gifs/mine.gif"

check "the nested help directory survived" \
	"grep -qx 'local note' /usr/share/xymon/help/mydocs/note.txt"

# The migration keeps anything it could not move rather than deleting
# it. Nothing here should have been unmovable, so a leftover means the
# move went wrong even though the transaction succeeded.
check "nothing had to be set aside as .rpmorig" \
	"! ls -d /usr/lib/xymon/client/etc.rpmorig /var/lib/xymon/www/*.rpmorig 2>/dev/null | grep -q ."

echo "== and the layout is the one this build ships =="

check "client config is in /etc, reachable the upstream way" \
	"test -f /etc/xymon-client/xymonclient.cfg &&
	 readlink /usr/lib/xymon/client/etc | grep -qx /etc/xymon-client"

for d in gifs help menu; do
	check "www/$d points at the static tree" \
		"readlink /var/lib/xymon/www/$d | grep -qx /usr/share/xymon/$d"
done

check "the generated directories are still real and writable" \
	"test -d /var/lib/xymon/www/rep -a ! -L /var/lib/xymon/www/rep"

check "the shipped content is reachable through the symlinks" \
	"test -f /var/lib/xymon/www/gifs/green.gif"

exit "$fail"
