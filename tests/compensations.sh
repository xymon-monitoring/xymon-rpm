#!/bin/sh
# Asserts that every upstream reference the spec cites is tracked.
#
# The spec compensates for what upstream does not offer yet, and each
# compensation names the pull request that will delete it -- CONTRIBUTING.md
# *When upstream is right but not yet available* makes that the condition on
# the override. This checks the half of that a machine can check: that the
# name leads somewhere.
#
# The two trackers are docs/upstream.md *Gaps sent back upstream* (build and
# install compensations) and README *Known gaps* (runtime shortfalls). A
# citation in neither is a workaround nobody will ever remove.
#
# It has teeth at the moment it matters. upstream.md says a proposal drops off
# its table once it merges, so when one does, the row goes and the citation
# left in the spec becomes untracked -- and this goes red, saying the
# compensation should now be deleted, on the day that becomes true.
#
# It does not check the converse, and cannot. The trackers legitimately list
# proposals the spec has not consumed yet, so "tracked but not cited" is a
# normal state, not a finding.
#
# What it cannot see at all is a compensation added with no citation: nothing
# here can define "compensation" by pattern. That case is caught in review, by
# the element CONTRIBUTING.md *Descriptions* requires.

set -eu

specs="rpm/xymon.spec rpm/xymon-release.spec"
trackers="docs/upstream.md README.md"

fail=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		fail=1
	fi
}

for f in $specs $trackers; do
	[ -f "$f" ] || { echo "NOT OK   $f not found -- run from the repository root"; exit 1; }
done

# Only the specs this repository writes. rpm/terabithia/ is archived reference
# material carrying Red Hat Bugzilla numbers (BZ #447156, BZ#732799), and
# build/mkindex.sh carries CSS colours (#161b22) and HTML entities -- all of
# which a bare #NNN pattern reads as pull requests.
# shellcheck disable=SC2086  # $specs is a list of paths; the split is the point
cited=$(grep -ohE 'xymon#[0-9]+' $specs | grep -oE '[0-9]+' | sort -u)

# Tracked means linked, not merely mentioned: a row cites the pull request or
# issue by URL, which is also what tests/docs.sh parses. Written to a file
# rather than a variable, so each assertion is a plain grep of one number.
tracked=/tmp/compensations-tracked-$$
trap 'rm -f "$tracked"' EXIT INT TERM
{
	sed -n '/^## Gaps sent back upstream/,/^## Drift detection/p' docs/upstream.md
	sed -n '/^## Known gaps/,/^## Testing/p' README.md
} | grep -oE '/(pull|issues)/[0-9]+' | grep -oE '[0-9]+' | sort -u > "$tracked"

echo "== every upstream reference the spec cites is tracked =="

[ -n "$cited" ] || { echo "NOT OK   no xymon#NNN citation found in the spec -- has the form changed?"; exit 1; }
[ -s "$tracked" ] || { echo "NOT OK   no tracked pull request parsed out of the two trackers"; exit 1; }

for n in $cited; do
	check "xymon#$n is in a tracker" "grep -qx $n $tracked"
done

# Without this the check above is optional: a citation written bare would
# simply not be seen. CONTRIBUTING.md *Descriptions* asks for the qualified
# form anyway, so a reader knows which repository to open.
# shellcheck disable=SC2086  # as above
bare=$(grep -nE '(^|[^a-z0-9])#[0-9]{3}([^0-9]|$)' $specs || :)
check "every upstream citation is written xymon#NNN, not #NNN" \
	"test -z \"$bare\""
[ -z "$bare" ] || printf '%s\n' "$bare" | sed 's/^/           /'

echo
if [ "$fail" -eq 0 ]; then
	echo "compensations.sh: all assertions passed"
else
	echo "compensations.sh: the spec cites something no tracker holds, or cites"
	echo "  it in a form this cannot follow."
	echo "  A pull request that merged: delete the workaround it justified."
	echo "  A compensation that is new: add it to docs/upstream.md *Gaps sent back"
	echo "  upstream*, or to README *Known gaps* if it is a runtime shortfall."
	echo "  A bare #NNN: write it xymon#NNN, so a reader knows which repository."
fi
exit "$fail"
