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

# el10 -> 10, fc44 -> 44. The tree is keyed on the bare number so one
# .repo file, using dnf's own $releasever, serves both families; dnf
# cannot choose between el and fc at expansion time. EL is 8/9/10 and
# Fedora 43/44, so they never collide.
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

# Empty the snapshot channel before this build is folded in, so the tree
# holds exactly what was just built. Pruning cannot do this: retention
# keeps every packaging rebuild of one upstream commit as a single build.
# Snapshot only -- the stable channel is what people pin to.
if [ "${XYMON_SNAPSHOT_RESET:-}" = "1" ]; then
	echo "== resetting the snapshot channel =="
	n=$(find "$repodir/xymon-snapshot" -name '*.rpm' 2>/dev/null | wc -l | tr -d ' ')
	rm -rf "${repodir:?}/xymon-snapshot"
	echo "  - dropped $n packages; the tree is rebuilt from this run alone"
fi

echo "== signing =="
# %_gpg_name comes from the caller's ~/.rpmmacros. Re-signing an
# already-signed package just replaces the signature.
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
# The stable channel keeps everything forever: people pin versions and
# roll back. Snapshots are pre-releases shipped disabled by default, so
# they are pruned to stop the tree growing without bound. Retention is
# per package directory and removes whole *builds*, never files: dropping
# half a build leaves a repository that resolves to a missing dependency.
#
# What is counted is upstream commits, and each keeps only its newest
# packaging rebuild. The two halves are not equivalent: rolling back on a
# snapshot channel means going back to a different state of Xymon, and an
# older packaging of the state you already have is not that. Counting
# builds instead spent all five slots on one upstream commit the day this
# repository merged five packaging changes, which is how the rule was
# found.
#
# It bounds the tree harder than counting builds did, not less: packaging
# rebuilds can no longer occupy more than one slot each, so the ceiling
# is keep x one build rather than keep x anything.
keep=${XYMON_SNAPSHOT_KEEP:-5}

# The build id is the Release field minus the dist tag: the upstream half
# 0.<date>git<sha>, plus the packaging half .<datetime>p<sha> when there
# is one. Fixed-width datetimes lead both halves, so a reverse sort is
# newest-first, and an id with no packaging half sorts below every
# rebuild of the same commit.
buildid() {
	printf '%s\n' "${1##*/}" \
	| sed -nE 's/.*-(0\.[0-9]{8}git[0-9a-f]+(\.[0-9]{12}p[0-9a-f]+)?)\..*/\1/p'
}

# The upstream half alone -- the grouping key.
upstreamid() {
	printf '%s\n' "${1##*/}" \
	| sed -nE 's/.*-(0\.[0-9]{8}git[0-9a-f]+)(\.[0-9]{12}p[0-9a-f]+)?\..*/\1/p'
}

if [ -d "$repodir/xymon-snapshot" ]; then
	echo "== pruning snapshots (keeping $keep upstream builds per directory, newest packaging of each) =="
	find "$repodir/xymon-snapshot" -name '*.rpm' -printf '%h\n' | sort -u | while read -r dir; do
		all=$(for f in "$dir"/*.rpm; do
			[ -e "$f" ] || continue
			printf '%s\t%s\n' "$(upstreamid "$f")" "$(buildid "$f")"
		done | sort -ru)
		# Newest first, so the first row of each upstream id is its newest
		# packaging rebuild. Everything not in this set goes, whether it is
		# a superseded rebuild or an upstream commit past the window.
		kept=$(printf '%s\n' "$all" | awk -F'\t' '!seen[$1]++' | head -n "$keep" | cut -f2)
		drop=$(printf '%s\n' "$all" | cut -f2 | while read -r b; do
			[ -n "$b" ] || continue
			printf '%s\n' "$kept" | grep -qxF "$b" || printf '%s\n' "$b"
		done)
		[ -n "$drop" ] || continue
		# Compare ids rather than globbing them: an id with no packaging
		# half is a prefix of every rebuild of the same commit, so
		# rm *"$b"* would take newer builds down with the old one.
		printf '%s\n' "$drop" | while read -r b; do
			[ -n "$b" ] || continue
			n=0
			for f in "$dir"/*.rpm; do
				[ -e "$f" ] || continue
				[ "$(buildid "$f")" = "$b" ] || continue
				rm -f "$f"
				n=$((n + 1))
			done
			# Named, not silent: a repository that quietly loses
			# builds looks like one that never had them. Say which of
			# the two rules dropped it -- they are not the same event.
			u=$(printf '%s\n' "$b" | sed -E 's/(\.[0-9]{12}p[0-9a-f]+)$//')
			if printf '%s\n' "$kept" | grep -q "^$u"; then
				why="superseded packaging of $u"
			else
				why="upstream build past the newest $keep"
			fi
			echo "  - ${dir#"$repodir"/}: dropped build $b ($n packages, $why)"
		done
	done
fi

# A channel that has no packages yet still needs metadata. createrepo_c
# on an empty directory produces valid repodata listing zero packages,
# and dnf then says "no match for argument" and carries on; with no
# repodata at all it gets a 404 for repomd.xml and fails the entire
# transaction, including packages from unrelated repositories. The
# shipped .repo file enables the stable channel, so until the first
# release lands that 404 is what every new user meets.
#
# The snapshot channel defines which releasever/arch combinations exist,
# so mirror its layout rather than hardcoding a list that would drift
# from the build matrix.
if [ -d "$repodir/xymon-snapshot" ]; then
	find "$repodir/xymon-snapshot" -mindepth 2 -maxdepth 2 -type d | while read -r d; do
		mkdir -p "$repodir/xymon/${d#"$repodir"/xymon-snapshot/}"
	done
fi

echo "== regenerating metadata =="
# Every channel/releasever/arch directory gets its own metadata; that is
# what a dnf baseurl points at. Not the tree root: the bootstrap
# xymon-release rpm lives there, and createrepo_c on the root would
# recursively merge every channel, distro and arch. Remove one an
# earlier run created.
rm -rf "$repodir/repodata"
find "$repodir" -mindepth 3 -maxdepth 3 -type d | sort -u | while read -r dir; do
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
