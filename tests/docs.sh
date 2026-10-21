#!/bin/sh
#
# Asserts that docs/upstream.md, and the tracking issue it links to, still
# describe reality.
#
# Everything here checks a claim that can change without anyone editing
# this repository: a pull request is merged, a file appears on `devel`, a
# PR grows a second commit that touches three more files. Prose cannot
# notice any of that. Every one of these assertions corresponds to a claim
# that was true when written and had gone wrong by the time it was
# checked.
#
# The doc and the issue are the input, not a copy of them: the origin column
# is parsed out of the doc, the state column out of the issue, and both are
# tested against the source. Hardcoding the
# expectations here would test this script against reality and leave the
# doc free to drift, which is the failure being prevented.
#
# Judgement claims ("no other packaging does this") are out of reach and
# are not attempted. So are the Debian, FreeBSD and Terabithia claims in
# deployment-strategies.md: verifying those means fetching a .deb and two
# port Makefiles, and they change on a scale of years rather than days.
#
# Needs a xymon checkout with an `origin` remote (default ./src, as the
# build workflow clones it) and, for the pull request assertions, gh
# authenticated against GitHub, to read the tracking issue and the upstream
# pull requests.

set -eu

src=${1:-src}
doc=docs/upstream.md
upstream=xymon-monitoring/xymon
packaging=xymon-monitoring/xymon-rpm

fail=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		fail=1
	fi
}

[ -f "$doc" ] || { echo "NOT OK   $doc not found -- run from the repository root"; exit 1; }
[ -d "$src/.git" ] || { echo "NOT OK   no xymon checkout at $src"; exit 1; }

git -C "$src" fetch -q origin main devel 2>/dev/null || :

echo "== the provenance table describes the files it names =="

# Rows are: | `file`[, `file`] | origin phrase | why |
# The origin phrase is a claim about devel, so test exactly that claim:
# "byte-identical"/"copied" must compare equal, "adapted" must exist and
# differ, and "written here" must not be there at all.
# Fed from a file, not a pipe: a `while` on the right-hand side of a pipe
# runs in a subshell, where the fail flag these checks set would be
# discarded and the suite would exit 0 with NOT OK lines on screen.
sed -n 's/^| `\([^|]*\)` *| *\([^|]*[^| ]\) *|.*/\1\t\2/p' "$doc" > "/tmp/docs-prov-$$"
while IFS="$(printf '\t')" read -r files origin; do
	for f in $(echo "$files" | tr ',' ' ' | tr -d '`'); do
		[ -n "$f" ] || continue
		[ -f "rpm/sources/$f" ] || {
			echo "NOT OK   rpm/sources/$f is named in $doc but not shipped"
			fail=1; continue
		}
		path=$(git -C "$src" ls-tree -r --name-only origin/devel |
		       grep -E "(^|/)$(echo "$f" | sed 's/[.[\*^$]/\\&/g')$" | head -1 || :)
		case "$origin" in
		*byte-identical*|*copied*)
			if [ -z "$path" ]; then
				echo "NOT OK   $f claims to come from devel, which does not have it"
			else
				git -C "$src" show "origin/devel:$path" > "/tmp/docs-$$" 2>/dev/null || :
				check "$f is byte-identical to devel's $path" \
					"cmp -s /tmp/docs-$$ rpm/sources/$f"
				rm -f "/tmp/docs-$$"
			fi
			;;
		*adapted*)
			if [ -z "$path" ]; then
				echo "NOT OK   $f claims to be adapted from devel, which does not have it"
			else
				git -C "$src" show "origin/devel:$path" > "/tmp/docs-$$" 2>/dev/null || :
				# Equal means it was copied, not adapted -- the row
				# understates where the file came from.
				check "$f differs from devel's $path, as 'adapted' claims" \
					"! cmp -s /tmp/docs-$$ rpm/sources/$f"
				rm -f "/tmp/docs-$$"
			fi
			;;
		*written\ here*)
			check "$f is not on devel, as 'written here' claims" \
				"test -z '$path'"
			;;
		esac
	done
done < "/tmp/docs-prov-$$"
rm -f "/tmp/docs-prov-$$"

echo "== the tracking issue's pull request table matches the pull requests =="

# The table is in an issue, not in this tree: its state column changes every
# time an upstream pull request moves, which no commit here marks. The doc's
# *Gaps sent back upstream* links to it, and that link is the one place its
# number is written, so the doc and these checks cannot point at two issues.
issue=$(sed -n '/^## Gaps sent back upstream/,/^## Drift detection/p' "$doc" |
	grep -oE 'xymon-rpm/issues/[0-9]+' | head -1 | grep -oE '[0-9]+$' || :)

if ! command -v gh >/dev/null 2>&1; then
	echo "NOT OK   gh not found -- the pull request assertions cannot run"
	fail=1
elif [ -z "$issue" ]; then
	echo "NOT OK   $doc *Gaps sent back upstream* links to no xymon-rpm issue"
	fail=1
elif ! gh issue view "$issue" --repo "$packaging" --json body --jq .body \
		> "/tmp/docs-body-$$" 2>/dev/null; then
	echo "NOT OK   cannot read xymon-rpm#$issue"
	fail=1
	rm -f "/tmp/docs-body-$$"
else
	# Rows are: | [xymon#NNN](url) | what it adds | open|draft |
	rows='s/^| \[xymon#\([0-9]\{1,\}\)\][^|]*|[^|]*| *\([a-z]*\) *|.*/\1 \2/p'
	sed -n "$rows" "/tmp/docs-body-$$" > "/tmp/docs-prs-$$"
	[ -s "/tmp/docs-prs-$$" ] || { echo "NOT OK   no PR rows parsed out of xymon-rpm#$issue"; fail=1; }

	# Through the issues API rather than gh pr view, because one row is an
	# upstream issue (xymon#444), which gh pr view cannot read.
	while read -r n claimed; do
		[ -n "$n" ] || continue
		real=$(gh api "repos/$upstream/issues/$n" \
			--jq 'if .pull_request then (if .pull_request.merged_at then "merged" elif .state == "closed" then "closed" elif .draft then "draft" else "open" end) else .state end' 2>/dev/null || echo "unknown")
		check "xymon#$n is $claimed" "test '$real' = '$claimed'"
	done < "/tmp/docs-prs-$$"

	# The issue names which PRs merge in any order. That list is only correct
	# while it is exactly the open, non-draft ones in the build and install
	# table -- it went stale the moment a sixth PR opened. The runtime table
	# is left out: its rows are not opt-in, and two of them are stacked. A
	# "merge in any order" claim needs at least two PRs to be about; with
	# fewer than two open the claim is degenerate, so the issue must not make
	# it and the check inverts to say so.
	sed -n '/^## Build and install/,/^## /p' "/tmp/docs-body-$$" |
		sed -n "$rows" > "/tmp/docs-build-$$"
	named=$(sed -n 's/^xymon#\([0-9, xymon#]*\)and xymon#\([0-9]\{1,\}\) merge in any order.*/\1 \2/p' "/tmp/docs-body-$$" |
		tr -dc '0-9 ' | tr -s ' ' '\n' | grep . | sort -u | tr '\n' ' ')
	open=$(awk '$2 == "open" { print $1 }' "/tmp/docs-build-$$" | sort -u | tr '\n' ' ')
	opencount=$(awk '$2 == "open"' "/tmp/docs-build-$$" | grep -c . || :)
	if [ "$opencount" -ge 2 ]; then
		check "the PRs named as order-independent are exactly the open ones" \
			"test '$named' = '$open'"
	else
		check "no order-independence claim while fewer than two PRs are open" \
			"test -z '$named'"
	fi

	# There was a check here that no row touched tests/. It guarded one
	# claim -- that xymon#421 needed no ordering check, being the only one of
	# these that touched tests/ -- and xymon#421 merged on 2026-08-22, so
	# there is no ordering left to protect. What remains of the premise, that
	# each row is a no-op for an existing build, is about what "make install"
	# produces, which a test change neither shows nor hides: xymon#411 proved
	# both halves at once, growing a test and, separately, an unconditional
	# mkdir. Read the diff; no proxy stands in for that.
	rm -f "/tmp/docs-prs-$$" "/tmp/docs-build-$$" "/tmp/docs-body-$$"
fi

echo "== what main does and does not carry =="

check "main still has no systemd unit, as the opening paragraph claims" \
	"! git -C $src ls-tree -r --name-only main | grep -qE '\.service(\.DIST)?$'"
check "main still has no SELinux policy, as the opening paragraph claims" \
	"! git -C $src ls-tree -r --name-only main | grep -qE '\.te$'"
# The same paragraph says main's only logrotate file is in its own
# unmaintained rpm/ packaging. If that stops being true the sentence needs
# rewriting either way.
check "main's logrotate files are only inside its own packagings" \
	"! git -C $src ls-tree -r --name-only main | grep -i logrotate | grep -qvE '^(rpm|debian)/'"

echo "== the unit's relationship to devel's =="

# The row claims eleven directives are verbatim. Spelled out in the doc, so
# the number is pinned here; the point of the check is that it moves when
# either unit changes.
git -C "$src" show origin/devel:tools/xymonlaunch.service |
	grep -vE '^\s*#|^\s*$|^\[' | sed 's/[[:space:]]*$//' | sort > "/tmp/docs-u1-$$"
grep -vE '^\s*#|^\s*$|^\[' rpm/sources/xymonlaunch.service |
	sed 's/[[:space:]]*$//' | sort > "/tmp/docs-u2-$$"
shared=$(comm -12 "/tmp/docs-u1-$$" "/tmp/docs-u2-$$" | grep -c . || :)
check "eleven directives are still verbatim from devel's unit (found $shared)" \
	"test '$shared' -eq 11"
rm -f "/tmp/docs-u1-$$" "/tmp/docs-u2-$$"

echo
if [ "$fail" -eq 0 ]; then
	echo "docs.sh: all assertions passed"
else
	echo "docs.sh: docs/upstream.md or its tracking issue no longer matches the"
	echo "  source -- update the doc, or the issue's row (drop it once merged)"
fi
exit "$fail"
