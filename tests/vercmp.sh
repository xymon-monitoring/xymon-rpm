#!/bin/sh
#
# The snapshot/release ordering is the one thing in this repo that silently
# does the wrong thing when it breaks: a bad Release string either strands
# snapshot users on an old build or drags stable users onto a snapshot.
# Neither shows up as a failed build, so assert it explicitly.
#
# Requires rpmdev-vercmp (rpmdevtools).

set -eu

fail=0

# want: $1 sorts strictly below $2
below() {
	# rpmdev-vercmp exit codes: 0 equal, 11 first newer, 12 second newer.
	# "below" means the second argument must win, so 12 is the pass.
	if rpmdev-vercmp "$1" "$2" >/dev/null 2>&1; then
		rc=0
	else
		rc=$?
	fi
	if [ "$rc" = 12 ]; then
		echo "ok       $1  <  $2"
	else
		echo "NOT OK   $1  is not below  $2  (rpmdev-vercmp rc=$rc)"
		fail=1
	fi
}

# The previous release upgrades to a snapshot of the next version.
below "4.3.30-1.el10" "4.3.31-0.20260730git3a07523.el10"

# Snapshots advance among themselves, by date then by nothing else.
below "4.3.31-0.20260730git3a07523.el10" "4.3.31-0.20260731gitdeadbee.el10"

# The real release supersedes every snapshot of itself. This is the one
# that a naive "Release: 1 + snapshot suffix" scheme gets backwards.
below "4.3.31-0.20260731gitdeadbee.el10" "4.3.31-1.el10"

# And the next release supersedes the previous one.
below "4.3.31-1.el10" "4.3.32-1.el10"

exit "$fail"
