#!/bin/sh
#
# Emit the .repo file users drop into /etc/yum.repos.d.
#
# $releasever and $basearch are expanded by dnf itself, not by this script,
# so one file serves every supported release and architecture. They are
# single-quoted below for exactly that reason.

set -eu

base=${XYMON_REPO_BASEURL:-https://xymon-monitoring.github.io/xymon-rpm}

# Where clients look for the signing key.
#
#   remote  served next to the packages -- for the file users curl
#           straight into /etc/yum.repos.d
#   local   /etc/pki/rpm-gpg -- for the copy inside xymon-release, which
#           installs the key itself, so it needs no network fetch and
#           arrives verified by that package's own signature
case "${1:-remote}" in
local)  gpgkey="file:///etc/pki/rpm-gpg/RPM-GPG-KEY-xymon" ;;
remote) gpgkey="$base/RPM-GPG-KEY-xymon" ;;
*)      echo "usage: mkrepofile.sh [remote|local]" >&2; exit 2 ;;
esac

# The minor-release caveat below is inside the heredoc, not above it: it is
# for whoever is looking at the installed file when dnf says it found
# nothing, and a comment in this generator never reaches them.
cat <<EOF
# HIGHLY EXPERIMENTAL: this packaging is new and has seen no production
# use. Layout, versioning and repository structure may still change
# without notice -- do not point production machines at it yet.
#
# A host pinned to a RHEL minor release (subscription-manager release
# --set=9.4) expands \$releasever to "9.4", where there is no tree, and
# every transaction fails on the 404. Set releasever=9 in every stanza
# below on such a host.
#
[xymon]
name=Xymon
baseurl=$base/xymon/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$gpgkey

# Built from upstream main, nightly when it or this packaging has moved.
# Disabled by default: these are pre-releases of the next version, and a
# machine that follows them is running code that has had no release
# testing. Enable deliberately, per host -- set enabled=1 below, which
# works anywhere, or run the command your dnf understands:
#
#     dnf config-manager --set-enabled xymon-snapshot      # dnf4, EL
#     dnf config-manager setopt xymon-snapshot.enabled=1   # dnf5, Fedora
#
[xymon-snapshot]
name=Xymon (development snapshots)
baseurl=$base/xymon-snapshot/\$releasever/\$basearch/
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=$gpgkey

# Previews, from xymon-experimental: main plus the pull requests of a
# milestone and the unreleased ones before it, most of them not reviewed
# yet. For testing, not
# production. Enable ONE preview channel, and not together with
# xymon-snapshot: a snapshot of the same version sorts above a preview, so
# dnf would install the snapshot.
#
# This one holds the 2 newest previews of every unreleased milestone: plain
# "dnf install xymon" takes the newest milestone, "dnf install
# xymon-4.3.32" that one.
#
#     dnf config-manager --set-enabled xymon-preview      # dnf4, EL
#     dnf config-manager setopt xymon-preview.enabled=1   # dnf5, Fedora
#
[xymon-preview]
name=Xymon (previews of unreleased milestones)
baseurl=$base/xymon-preview/\$releasever/\$basearch/
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=$gpgkey

# The previews of the next release alone, e.g. 4.3.31 until it is released,
# then 4.3.32: a plain "dnf upgrade" follows the release that is coming
# rather than the newest milestone. The usual choice; enable it instead of
# xymon-preview, never with it.
#
#     dnf config-manager --set-enabled xymon-preview-next      # dnf4, EL
#     dnf config-manager setopt xymon-preview-next.enabled=1   # dnf5, Fedora
#
[xymon-preview-next]
name=Xymon (previews of the next release)
baseurl=$base/xymon-preview-next/\$releasever/\$basearch/
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=$gpgkey
EOF
