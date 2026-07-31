#!/bin/bash
#
# Sign the built packages and fold them into the published dnf repository.
#
#   publish.sh <artifacts-dir> <repo-dir>
#
# <artifacts-dir> holds one subdirectory per build target, each containing
# that target's .rpm files. <repo-dir> is a checkout of the published
# repository, which is updated in place; the caller commits and pushes it.
#
# Existing packages are kept. A dnf repository is not a snapshot of the
# latest build -- users pin versions, roll back, and install older releases,
# so removing a published package breaks them. Only the metadata is
# regenerated.

set -euo pipefail

artifacts=${1:?usage: publish.sh <artifacts-dir> <repo-dir>}
repodir=${2:?usage: publish.sh <artifacts-dir> <repo-dir>}

# A release build has no snapshot marker in its Release field; anything
# else is a snapshot. Keeping the two in separate repositories is what
# stops a stable user being silently moved onto a nightly build.
channel_for() {
	case "$1" in
	*-0.*git*) echo "xymon-snapshot" ;;
	*)         echo "xymon" ;;
	esac
}

# xymon-4.3.31-0.20260723git3a07523.el10.x86_64.rpm -> el10
dist_for() {
	echo "$1" | sed -E 's/.*\.((el|fc)[0-9]+)\.[^.]+\.rpm$/\1/'
}

# el10 -> 10, fc44 -> 44.
#
# The published tree is keyed on the bare number so that a single .repo
# file, using dnf's own $releasever, serves both distribution families.
# Keying it on the dist tag instead would need one repo file per family,
# since dnf cannot choose between el and fc at expansion time. EL is 8/9/10
# and Fedora is 43/44, so the two never collide.
releasever_for() {
	echo "$1" | tr -dc '0-9'
}

# ... .x86_64.rpm -> x86_64 ; source packages are filed under SRPMS
arch_for() {
	case "$1" in
	*.src.rpm) echo "SRPMS" ;;
	*)         echo "$1" | sed -E 's/.*\.([^.]+)\.rpm$/\1/' ;;
	esac
}

echo "== signing =="
# %_gpg_name is set by the caller via ~/.rpmmacros; rpm --addsign is
# idempotent in the sense that re-signing an already-signed package simply
# replaces the signature.
find "$artifacts" -name '*.rpm' -print0 | xargs -0 -r rpm --addsign

echo "== filing packages =="
find "$artifacts" -name '*.rpm' | while read -r pkg; do
	base=$(basename "$pkg")
	dist=$(dist_for "$base")
	case "$dist" in
	el*|fc*) ;;
	*) echo "  skip (no dist tag): $base"; continue ;;
	esac
	dest="$repodir/$(channel_for "$base")/$(releasever_for "$dist")/$(arch_for "$base")"
	mkdir -p "$dest"
	# Never overwrite: a published NEVRA is immutable. Two different
	# builds producing the same NEVRA is a versioning bug, not something
	# to paper over silently.
	if [ -e "$dest/$base" ]; then
		echo "  already published, leaving alone: $base"
	else
		cp -p "$pkg" "$dest/$base"
		echo "  + ${dest#"$repodir"/}/$base"
	fi
done

echo "== regenerating metadata =="
# Every directory that actually holds packages gets its own metadata; that
# is what a dnf baseurl points at.
find "$repodir" -name '*.rpm' -printf '%h\n' | sort -u | while read -r dir; do
	createrepo_c --update --quiet "$dir"
	# Sign the metadata as well as the packages, so the package *list* is
	# verifiable too. Without this, repo_gpgcheck=1 cannot be used and a
	# man-in-the-middle can still hide an update.
	rm -f "$dir/repodata/repomd.xml.asc"
	gpg --batch --yes --detach-sign --armor "$dir/repodata/repomd.xml"
	echo "  ${dir#"$repodir"/}"
done

echo "== published tree =="
find "$repodir" -name '*.rpm' | sed "s|$repodir/||" | sort
