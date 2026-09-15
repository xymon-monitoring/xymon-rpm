#!/bin/sh
#
# What build/publish.sh does to the published tree. Nothing here touches
# the real repository: it publishes into a temporary directory with a
# throwaway signing key, so the assertions can be about behaviour rather
# than about not breaking anything.
#
# Two of these are regressions that reached users. The stable channel had
# no metadata until its first release, and dnf does not read that as an
# empty repository -- it gets a 404 for repomd.xml and fails the entire
# transaction, including packages from unrelated repositories, so the
# shipped .repo file broke dnf outright on any machine that installed it.
# And retention counts upstream commits rather than files, which is only
# correct if a build's packages are removed together; half a build left
# behind resolves to a missing dependency.
#
# Run from the repository root with the built packages in ./out, or in a
# directory given as the first argument. Needs createrepo_c, rpm-sign and
# gpg, so it runs inside a distro container.

set -eu

fail=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		fail=1
	fi
}

rpmdir=${1:-out}
rpms=$(find "$rpmdir" -name '*.rpm' 2>/dev/null | wc -l)
if [ "$rpms" -lt 2 ]; then
	echo "NOT OK   need at least two rpms in $rpmdir, found $rpms"
	exit 1
fi
for t in createrepo_c gpg rpmsign; do
	command -v "$t" >/dev/null 2>&1 || { echo "NOT OK   $t is missing"; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

cat > "$work/keyparams" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign
Name-Real: xymon-rpm test key
Expire-Date: 0
%no-protection
%commit
EOF
gpg --batch --generate-key "$work/keyparams" >/dev/null 2>&1
echo "%_gpg_name xymon-rpm test key" > "$work/rpmmacros"
HOME_ORIG=$HOME
export HOME=$work
cp "$work/rpmmacros" "$work/.rpmmacros"

# A snapshot-versioned package, which is what a build of main produces.
snap=$(find "$rpmdir" -name 'xymon-client-*0.*git*.rpm' ! -name '*debuginfo*' | head -1)
[ -n "$snap" ] || { echo "NOT OK   no snapshot-versioned rpm in $rpmdir"; exit 1; }
# Absolute, because publish.sh is handed a temporary directory to work in.
snap=$(cd "$(dirname "$snap")" && pwd)/$(basename "$snap")

repo=$work/repo
art=$work/artifacts/target
mkdir -p "$repo" "$art"
cp "$snap" "$art/"

./build/publish.sh "$art/.." "$repo" > "$work/publish.log" 2>&1 ||
	{ echo "NOT OK   publish.sh failed"; sed 's/^/    /' "$work/publish.log"; exit 1; }

echo "== a snapshot-only tree still gives the stable channel a usable repository =="

check "the snapshot package was filed under xymon-snapshot" \
	"find $repo/xymon-snapshot -name '*.rpm' | grep -q ."

# The regression: with no release ever published, the stable channel used
# to be absent rather than empty.
check "the stable channel exists even with no release" \
	"test -d $repo/xymon"
check "every published directory has repodata/repomd.xml" \
	"test \$(find $repo -mindepth 3 -maxdepth 3 -type d | wc -l) -eq \$(find $repo -name repomd.xml | wc -l)"
check "the stable channel's metadata is present" \
	"find $repo/xymon -name repomd.xml | grep -q ."
# repo_gpgcheck=1 is set in the shipped .repo file, so unsigned metadata
# would trade a 404 for a signature error.
check "the stable channel's metadata is signed" \
	"test \$(find $repo/xymon -name repomd.xml | wc -l) -eq \$(find $repo/xymon -name repomd.xml.asc | wc -l)"
check "the stable channel really is empty, not accidentally populated" \
	"test -z \"\$(find $repo/xymon -name '*.rpm')\""
check "the stable layout mirrors the snapshot layout" \
	"test \"\$(cd $repo/xymon && find . -type d -not -path '*/repodata*' | sort)\" = \"\$(cd $repo/xymon-snapshot && find . -type d -not -path '*/repodata*' | sort)\""

echo "== the tree root is not itself a repository =="
# createrepo_c on the root would recursively merge every channel, distro
# and arch into one signed repository.
check "no repodata at the tree root" \
	"test ! -d $repo/repodata"

echo "== a published NEVRA is immutable =="
before=$(md5sum "$repo"/xymon-snapshot/*/*/"$(basename "$snap")" | cut -d' ' -f1)
./build/publish.sh "$art/.." "$repo" >> "$work/publish.log" 2>&1
after=$(md5sum "$repo"/xymon-snapshot/*/*/"$(basename "$snap")" | cut -d' ' -f1)
check "republishing the same build leaves the package alone" \
	"test '$before' = '$after'"
check "and says so rather than silently overwriting" \
	"grep -q 'already published' $work/publish.log"

echo "== retention keeps upstream builds, one packaging rebuild each =="
# Two dimensions, because the rule has two. Several packaging rebuilds of
# one upstream commit are what a busy day in this repository produces;
# several upstream commits are what a user rolls back across. Counting
# builds let the first evict the second entirely -- five packaging merges
# in one morning left the published tree holding one upstream commit.
dir=$(find "$repo/xymon-snapshot" -name '*.rpm' -printf '%h\n' | head -1)
base=$(basename "$snap")
upstream_ids() {
	find "$dir" -name '*.rpm' -printf '%f\n' |
		sed -nE 's/.*-(0\.[0-9]{8}git[0-9a-f]+)\..*/\1/p' | sort -u
}
# three more packaging rebuilds of the commit just published
i=1
while [ $i -le 3 ]; do
	cp "$dir/$base" "$dir/$(echo "$base" | sed "s/p[0-9a-f]*\./p00000$i./")" 2>/dev/null || :
	i=$((i + 1))
done
# and four older upstream commits, one packaging rebuild each
i=1
while [ $i -le 4 ]; do
	cp "$dir/$base" \
		"$dir/$(echo "$base" | sed "s/0\.[0-9]\{8\}git[0-9a-f]*\./0.2026010${i}git000000${i}./")" \
		2>/dev/null || :
	i=$((i + 1))
done
published=$(printf '%s\n' "$base" | sed -nE 's/.*-(0\.[0-9]{8}git[0-9a-f]+)\..*/\1/p')
total_before=$(find "$dir" -name '*.rpm' | wc -l)
XYMON_SNAPSHOT_KEEP=3 ./build/publish.sh "$art/.." "$repo" > "$work/prune.log" 2>&1
kept=$(find "$dir" -name '*.rpm' | wc -l)
check "pruning happened at all (had $total_before)" \
	"test $kept -lt $total_before"
check "it kept three upstream commits, not three files" \
	"test \$(upstream_ids | grep -c .) -eq 3"
check "the newest upstream commit survived the packaging churn" \
	"upstream_ids | grep -qxF '$published'"
check "and it kept one packaging rebuild of it, not four" \
	"test \$(find $dir -name \"*$published*\" -printf '%f\\n' |
		 sed -nE 's/.*-(0\\.[0-9]{8}git[0-9a-f]+\\.[0-9]{12}p[0-9a-f]+)\\..*/\\1/p' |
		 sort -u | grep -c .) -eq 1"
check "a superseded packaging rebuild says why it went" \
	"grep -q 'superseded packaging of' $work/prune.log"
check "an upstream commit past the window says why it went" \
	"grep -q 'upstream build past the newest' $work/prune.log"

echo "== reset republishes from this run alone =="
XYMON_SNAPSHOT_RESET=1 ./build/publish.sh "$art/.." "$repo" > "$work/reset.log" 2>&1
check "the snapshot channel holds only this run's package" \
	"test \$(find $repo/xymon-snapshot -name '*.rpm' | wc -l) -eq 1"
check "the reset is announced" \
	"grep -q 'resetting the snapshot channel' $work/reset.log"
check "the stable channel survived the reset" \
	"find $repo/xymon -name repomd.xml | grep -q ."

export HOME=$HOME_ORIG
[ "$fail" = 0 ] && echo "publish tests passed" || echo "publish tests FAILED"
exit "$fail"
