#!/bin/bash
#
#   mkindex.sh <repo-dir>
#
# Generate browsable index pages for the published tree.
#
# dnf never needs these -- it fetches repodata/repomd.xml by exact path and
# never asks for a listing. They exist because GitHub Pages has no
# autoindex, so without them a person opening any directory in a browser
# gets a bare 404 and reasonably concludes the repository is broken.

set -euo pipefail

repodir=${1:?usage: mkindex.sh <repo-dir>}
base=${XYMON_REPO_BASEURL:-https://xymon-monitoring.github.io/xymon-rpm}
fpr=$(sed -n 's/^ *FINGERPRINT=//p' "$(dirname "$0")/../rpm/fingerprint" 2>/dev/null || true)

html_head() {
	cat <<-EOF
	<!doctype html>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>$1</title>
	<style>
	  body { font-family: system-ui, sans-serif; line-height: 1.5;
	         max-width: 52rem; margin: 2rem auto; padding: 0 1rem; }
	  code, pre { font-family: ui-monospace, monospace; }
	  pre { background: #f6f8fa; padding: .75rem 1rem; overflow-x: auto; }
	  table { border-collapse: collapse; width: 100%; }
	  td { padding: .2rem .6rem .2rem 0; white-space: nowrap; }
	  td.size { text-align: right; color: #666; }
	  a.up { color: #666; }
	  @media (prefers-color-scheme: dark) {
	    body { background: #0d1117; color: #e6edf3; }
	    pre { background: #161b22; }
	    a { color: #6cb6ff; } td.size, a.up { color: #9aa4ae; }
	  }
	</style>
	<h1>$1</h1>
	EOF
}

# --- per-directory listings -------------------------------------------
find "$repodir" -type d ! -path '*/.git*' ! -name repodata | while read -r dir; do
	rel=${dir#"$repodir"}
	rel=${rel#/}
	{
		html_head "${rel:-Xymon RPM repository}/"
		[ -n "$rel" ] && echo '<p><a class="up" href="../">&#8592; parent directory</a></p>'
		echo '<table>'
		for entry in "$dir"/*/; do
			[ -d "$entry" ] || continue
			name=$(basename "$entry")
			printf '<tr><td><a href="%s/">%s/</a></td><td class="size"></td></tr>\n' \
				"$name" "$name"
		done
		for entry in "$dir"/*; do
			[ -f "$entry" ] || continue
			name=$(basename "$entry")
			case "$name" in index.html|.nojekyll) continue ;; esac
			size=$(( ($(wc -c < "$entry") + 1023) / 1024 ))
			printf '<tr><td><a href="%s">%s</a></td><td class="size">%s KB</td></tr>\n' \
				"$name" "$name" "$size"
		done
		echo '</table>'
	} > "$dir/index.html"
done

# --- root landing page ------------------------------------------------
{
	html_head "Xymon RPM packages"
	cat <<-EOF
	<p>Official RPM packages for
	<a href="https://github.com/xymon-monitoring/xymon">Xymon</a>, built from
	source with no downstream patches. Packaging lives in
	<a href="https://github.com/xymon-monitoring/xymon-rpm">xymon-rpm</a>.</p>

	<h2>Install</h2>
	<pre>dnf install $base/xymon-release-1-1.noarch.rpm
	dnf install xymon          # server
	dnf install xymon-client   # client only</pre>
	<p>The first command adds the repository and installs the signing key
	in one step. If you would rather not install a package to do that,
	fetch <a href="xymon.repo">xymon.repo</a> into
	<code>/etc/yum.repos.d/</code> instead.</p>

	<p>Supported: EL8, EL9, EL10 and Fedora 43, 44 on x86_64.</p>

	<h2>Channels</h2>
	<table>
	  <tr><td><a href="xymon/">xymon/</a></td>
	      <td>tagged releases &mdash; enabled by default</td></tr>
	  <tr><td><a href="xymon-snapshot/">xymon-snapshot/</a></td>
	      <td>builds from the development branch &mdash; disabled by default</td></tr>
	</table>

	<p>Snapshots are pre-releases of the next version and have had no release
	testing. Enable them deliberately, per host:</p>
	<pre>dnf config-manager --set-enabled xymon-snapshot</pre>

	<h2>Signing</h2>
	<p>Packages and repository metadata are both signed. Verify the
	<a href="RPM-GPG-KEY-xymon">public key</a> against this fingerprint,
	which is also published in the
	<a href="https://github.com/xymon-monitoring/xymon-rpm#installing">repository README</a>
	&mdash; a fingerprint served only from here would prove nothing.</p>
	<pre>${fpr:-see the repository README}</pre>
	EOF
} > "$repodir/index.html"

echo "index pages written"
