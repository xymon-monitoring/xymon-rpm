#!/bin/sh
#
# Emit the .repo file users drop into /etc/yum.repos.d.
#
# $releasever and $basearch are expanded by dnf itself, not by this script,
# so one file serves every supported release and architecture. They are
# single-quoted below for exactly that reason.

set -eu

base=${XYMON_REPO_BASEURL:-https://xymon-monitoring.github.io/xymon-rpm}

# Where clients should look for the signing key.
#
#   remote  the copy served next to the packages -- correct for the file
#           users curl straight into /etc/yum.repos.d
#   local   /etc/pki/rpm-gpg -- correct for the copy inside xymon-release,
#           which installs the key itself, so no network fetch is needed
#           and the key arrives verified by that package's own signature
case "${1:-remote}" in
local)  gpgkey="file://%s" ; gpgkey=$(printf "$gpgkey" /etc/pki/rpm-gpg/RPM-GPG-KEY-xymon) ;;
remote) gpgkey="$base/RPM-GPG-KEY-xymon" ;;
*)      echo "usage: mkrepofile.sh [remote|local]" >&2; exit 2 ;;
esac

# A host pinned to a RHEL minor release (subscription-manager release
# --set=9.4) expands $releasever to "9.4" and will not find the tree. Such
# hosts should set releasever=9 in this file.
cat <<EOF
# HIGHLY EXPERIMENTAL: this packaging is new and has seen no production
# use. Layout, versioning and repository structure may still change
# without notice -- do not point production machines at it yet.
#
[xymon]
name=Xymon
baseurl=$base/xymon/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$gpgkey

# Built from the tip of the development branch, several times a week.
# Disabled by default: these are pre-releases of the next version, and a
# machine that follows them is running code that has had no release
# testing. Enable deliberately, per host:
#
#     dnf config-manager --set-enabled xymon-snapshot
#
[xymon-snapshot]
name=Xymon (development snapshots)
baseurl=$base/xymon-snapshot/\$releasever/\$basearch/
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=$gpgkey
EOF
