#!/bin/sh
#
# Asserts that docs/upstream.md still describes reality.
#
# Everything here checks a claim that can change without anyone editing
# this repository: a pull request is merged, a file appears on `devel`, a
# PR grows a second commit that touches three more files. Prose cannot
# notice any of that. Every one of these assertions corresponds to a claim
# that was true when written and had gone wrong by the time it was
# checked.
#
# The doc is the input, not a copy of it: the origin column and the state
# column are parsed out and tested against the source. Hardcoding the
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
# authenticated against the upstream repository.

set -eu

src=${1:-src}
doc=docs/upstream.md
upstream=xymon-monitoring/xymon

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

echo "== the pull request table matches the pull requests =="

if ! command -v gh >/dev/null 2>&1; then
	echo "NOT OK   gh not found -- the pull request assertions cannot run"
	fail=1
else
	# Rows are: | [#NNN](url) | what it adds | open|draft |
	sed -n 's/^| \[#\([0-9]\{1,\}\)\][^|]*|[^|]*| *\([a-z]*\) *|.*/\1 \2/p' "$doc" > "/tmp/docs-prs-$$"
	[ -s "/tmp/docs-prs-$$" ] || { echo "NOT OK   no PR rows parsed out of $doc"; fail=1; }

	while read -r n claimed; do
		[ -n "$n" ] || continue
		real=$(gh pr view "$n" --repo "$upstream" --json state,isDraft \
			--jq 'if .state != "OPEN" then (.state|ascii_downcase) elif .isDraft then "draft" else "open" end' 2>/dev/null || echo "unknown")
		check "#$n is $claimed" "test '$real' = '$claimed'"
	done < "/tmp/docs-prs-$$"

	# The doc names which PRs merge in any order. That list is only correct
	# while it is exactly the open, non-draft ones in the table -- it went
	# stale the moment a sixth PR opened.
	named=$(sed -n 's/^#\([0-9, #]*\)and #\([0-9]\{1,\}\) merge in any order.*/\1 \2/p' "$doc" |
		tr -dc '0-9 ' | tr -s ' ' '\n' | grep . | sort -u | tr '\n' ' ')
	open=$(awk '$2 == "open" { print $1 }' "/tmp/docs-prs-$$" | sort -u | tr '\n' ' ')
	check "the PRs named as order-independent are exactly the open ones" \
		"test '$named' = '$open'"

	# "it is the only one of these PRs touching tests/": if a build PR grows
	# a test change, the two are no longer independent.
	while read -r n _; do
		[ -n "$n" ] || continue
		check "#$n touches no files under tests/" \
			"! gh pr diff $n --repo $upstream --name-only 2>/dev/null | grep -q '^tests/'"
	done < "/tmp/docs-prs-$$"
	rm -f "/tmp/docs-prs-$$"
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
	echo "docs.sh: docs/upstream.md no longer matches the source -- update the doc"
fi
exit "$fail"
