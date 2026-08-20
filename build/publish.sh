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
# A reset empties the snapshot channel before this build's packages are
# folded in, so the tree ends up holding exactly what was just built.
# Pruning cannot achieve that: retention counts upstream build ids and
# keeps every packaging rebuild of one commit as a unit, so a long run
# of packaging-only changes accumulates within a single "build".
#
# Only ever the snapshot channel: the stable one is what people pin to,
# and removing a published release breaks them.
if [ "${XYMON_SNAPSHOT_RESET:-}" = "1" ]; then
	echo "== resetting the snapshot channel =="
	n=$(find "$repodir/xymon-snapshot" -name '*.rpm' 2>/dev/null | wc -l | tr -d ' ')
	rm -rf "${repodir:?}/xymon-snapshot"
	echo "  - dropped $n packages; the tree is rebuilt from this run alone"
fi

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

# --- snapshot retention ------------------------------------------------
#
# The stable channel keeps everything forever: people pin versions and roll
# back, so removing a published release breaks them. Snapshots are
# disposable by definition -- they are pre-releases of a version that has
# not been tested, shipped disabled by default -- so they are pruned to
# stop the published tree growing without bound.
#
# Retention is per package directory and counts *builds*, not files: one
# build produces several packages, and dropping half of one would leave a
# repository that resolves to a missing dependency.
keep=${XYMON_SNAPSHOT_KEEP:-5}

# The build id is the whole Release field minus the dist tag: the
# upstream half 0.<date>git<sha>, plus the packaging half
# .<datetime>p<sha> when the build has one. Counting the packaging half
# too is what bounds the tree -- while upstream sits still, packaging
# changes would otherwise pile up inside one upstream id forever, and no
# retention setting would ever remove them.
#
# Fixed-width datetimes lead both halves, so a plain reverse sort is
# newest-first; an id with no packaging half sorts below every rebuild
# of the same commit, which is the right order.
buildid() {
	printf '%s\n' "${1##*/}" \
	| sed -nE 's/.*-(0\.[0-9]{8}git[0-9a-f]+(\.[0-9]{12}p[0-9a-f]+)?)\..*/\1/p'
}

if [ -d "$repodir/xymon-snapshot" ]; then
	echo "== pruning snapshots (keeping the newest $keep builds per directory) =="
	find "$repodir/xymon-snapshot" -name '*.rpm' -printf '%h\n' | sort -u | while read -r dir; do
		all=$(for f in "$dir"/*.rpm; do
			[ -e "$f" ] || continue
			buildid "$f"
		done | sort -ru)
		total=$(echo "$all" | grep -c . || :)
		[ "$total" -le "$keep" ] && continue
		# Compare ids rather than globbing them: an id with no packaging
		# half is a prefix of every rebuild of the same commit, so
		# rm *"$b"* would take newer builds down with the old one.
		echo "$all" | tail -n +$((keep + 1)) | while read -r b; do
			[ -n "$b" ] || continue
			n=0
			for f in "$dir"/*.rpm; do
				[ -e "$f" ] || continue
				[ "$(buildid "$f")" = "$b" ] || continue
				rm -f "$f"
				n=$((n + 1))
			done
			# Say what was removed rather than pruning silently: a
			# repository that quietly loses builds looks like one that
			# never had them.
			echo "  - ${dir#"$repodir"/}: dropped build $b ($n packages)"
		done
	done
fi

echo "== regenerating metadata =="
# Every directory that actually holds packages gets its own metadata; that
# is what a dnf baseurl points at. The tree root is not one of them: the
# bootstrap xymon-release rpm lives there, and running createrepo_c on the
# root would generate a signed repodata recursively merging every channel,
# distro and arch. Remove the one an earlier run created.
rm -rf "$repodir/repodata"
find "$repodir" -name '*.rpm' -printf '%h\n' | sort -u | while read -r dir; do
	[ "$dir" = "$repodir" ] && continue
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
