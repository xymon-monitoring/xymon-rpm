# Xymon RPM packages

Official RPM packaging for [Xymon](https://github.com/xymon-monitoring/xymon),
built from the upstream tree with **no source patches** — the spec has zero
`Patch:` lines. Anything Xymon itself needs is fixed upstream, not here.

> [!WARNING]
> **Highly experimental.** New packaging with no production use. Package
> layout, versioning, and repository structure may still change without
> notice — do not point production machines at it yet.

## Packages

| Package | Contents |
| --- | --- |
| `xymon` | the server, including the client component it runs on itself |
| `xymon-client` | the same client packaged alone, for every non-server host |
| `xymon-client-local` | `xymond_client` on a client, for local threshold analysis |
| `xymon-devel` | headers, static libraries, and a pkg-config file (`xymon.pc`) for building modules; pulls in `pcre2-devel` |
| `xymon-tools` | diagnostics: stackio, locator, tree, availability, loadhosts |

`xymon` and `xymon-client` **conflict**: a host is a server or a client,
never both. See [docs/deployment-strategies.md](docs/deployment-strategies.md)
for why, and how Debian, Terabithia and FreeBSD packaged the same split.

`xymon-devel` and `xymon-tools` exist because Xymon's own build discards
both: `make install` ships no headers or libraries, and `lib/` has no install
rule for the tools it builds.

## Installing

**There has been no release yet**, so the stable channel the repo file enables
is empty — it answers, and holds no package. Everything goes to the snapshot
channel, which ships disabled, so enabling it is what makes `dnf install` find
anything today. The release procedure is the same without that step and is
below.

Published for **x86_64 only**. The repo file enables the stable channel on
every host that installs it, and no tree exists for another architecture, so
on aarch64 the 404 fails every `dnf` transaction on that machine — including
ones that have nothing to do with Xymon. Do not install the repo file there.

### Snapshots, on EL 8, 9 and 10

```sh
# config-manager lives in dnf-plugins-core, which EL does not install by
# default. On a server this arrives anyway with epel-release; name it so a
# client-only host works too.
dnf install dnf-plugins-core

# Server only, and not where Xymon comes from -- these packages are in
# neither EPEL nor Fedora. It is for fping, which the server pulls and which
# no RHEL repository carries, neither base nor CRB.
dnf install epel-release

curl -fsSLo /etc/yum.repos.d/xymon.repo \
  https://xymon-monitoring.github.io/xymon-rpm/xymon.repo
dnf config-manager --set-enabled xymon-snapshot

dnf install xymon          # server
dnf install xymon-client   # client only
```

### Snapshots, on Fedora

`config-manager` takes a different argument under dnf5, and ships in
`dnf5-plugins` rather than in dnf5 itself. fping is in Fedora's base, so there
is no EPEL step at all.

```sh
# config-manager is a dnf5 plugin, recommended by dnf5 rather than required:
# present on a full Fedora install, absent on fedora-minimal and wherever
# install_weak_deps=false. Named the way dnf5 names it when it is missing.
dnf install 'dnf5-command(config-manager)'

curl -fsSLo /etc/yum.repos.d/xymon.repo \
  https://xymon-monitoring.github.io/xymon-rpm/xymon.repo
dnf config-manager setopt xymon-snapshot.enabled=1

dnf install xymon          # server
dnf install xymon-client   # client only
```

### Releases, once there is one

The repo file enables the stable channel itself, so the `config-manager` line
goes — and with it the reason a client-only EL host needed `dnf-plugins-core`:

```sh
dnf install epel-release   # EL, server only

curl -fsSLo /etc/yum.repos.d/xymon.repo \
  https://xymon-monitoring.github.io/xymon-rpm/xymon.repo

dnf install xymon          # server
dnf install xymon-client   # client only
```

Every host runs the same unit, `xymonlaunch.service`, which picks the server
or client role by which package is installed. A client-only host sets the
server address (`XYMSRV`) in `/etc/xymon-client/xymonclient.cfg`, then runs
`systemctl enable --now xymonlaunch`. Installing the server on a client host
fails on the package conflict, by design. Changing a host's role is one
transaction:

```sh
dnf swap xymon-client xymon     # promote a client to the server
dnf swap xymon xymon-client     # demote a server to a client
systemctl restart xymonlaunch   # the swap stops the old role but starts
                                # nothing; this brings the new one up
```

Demoting also needs `XYMSRV` set afterwards, and a host installed before the
packages conflicted needs the same swap before `dnf upgrade` will resolve.
Both, plus where every file lives and everyday admin tasks, are in
[docs/admin-guide.md](docs/admin-guide.md).

Packages and repository metadata are signed; verify the key against this
fingerprint (see [docs/signing.md](docs/signing.md)):

```
Xymon Project (RPM signing key)
BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

Snapshots built from `main` are in the same repo file, and ship disabled on
purpose: they are pre-releases of the next version, so a machine that follows
them runs code no release has tested. Enabling one is a per-host decision, so
the repo file states it rather than making it: the stanza is there with
`enabled=0`, and the command sits in a comment beside it.

## Targets

| Target | Container | Published |
| --- | --- | --- |
| `el8` | `almalinux:8` | yes |
| `el9` | `almalinux:9` | yes |
| `el10` | `almalinux:10` | yes |
| `fc43` | `fedora:43` | yes |
| `fc44` | `fedora:44` | yes |
| `stream9` | `quay.io/centos/centos:stream9` | no — canary |
| `stream10` | `quay.io/centos/centos:stream10` | no — canary |
| `fedora-rawhide` | `fedora:rawhide` | no — canary |
| `selinux` | `almalinux:10` | no — builds the policy with `--with selinux` |

EL builds run on AlmaLinux, a rebuild of *released* RHEL, so they cannot
need a symbol version RHEL lacks; the dist tag carries no vendor marker, so
an `.el8` package runs on RHEL, Rocky, Oracle and Alma alike. CentOS Stream
previews the next RHEL minor, so it is a canary alongside rawhide — allowed
to fail, never published. Images are pinned so a moving tag cannot silently
change the dist tag. Fedora is carried at N and N-1.

## Layout

```
rpm/xymon.spec      the spec; no patches (map: docs/spec-structure.md)
rpm/xymon-release.spec  the bootstrap repo/key package (noarch, no dist tag)
rpm/baseversion     the version main is working toward (see Versioning)
rpm/sources/        runtime integration (unit, drop-ins, logrotate, sysusers, ...)
rpm/terabithia/     archived reference material, not built
build/              publish.sh signs and folds packages into the published tree;
                    mkrepofile.sh and mkindex.sh generate the .repo file and index
docs/               admin-guide, deployment-strategies, upstream, signing,
                    selinux, spec-structure, build-pipeline, testing, roadmap
tests/              see Testing
```

## Versioning

Two channels, which must sort correctly or dnf does the wrong thing silently.

| Built from | Version | Release |
| --- | --- | --- |
| tag `rel-X.Y.Z` | `X.Y.Z` | `<n>%{?dist}`, default `1` |
| `main` | contents of `rpm/baseversion` | `0.<date>git<sha>.<pkgdate>p<pkgsha>%{?dist}` |

A snapshot is a *pre-release of the next version* (`Release` starts with
`0.`), naming the upstream commit and then the last commit here that could
change a package — one touching `rpm/`, `build/` or `.github/`. That second
pair matters because a published NEVRA is immutable: without it a
packaging-only fix rebuilds the same NEVRA and never ships. Keying on `HEAD`
instead would mint a new NEVRA for every docs commit, so docs-only pushes
skip the build. The packaging datetime (UTC) does the ordering.

```
4.3.30-1
 -> 4.3.31-0.20260730git3a07523.202607301210pab12cd3   upgrade
 -> 4.3.31-0.20260731gitdeadbee.202607301210pab12cd3   upgrade (upstream moved)
 -> 4.3.31-0.20260731gitdeadbee.202608011535p9f8e7d6   upgrade (packaging moved)
 -> 4.3.31-1                                           upgrade (release lands)
```

Snapshot users are absorbed into the stable channel when the release lands.
A packaging-only fix to a *released* version ships by re-dispatching the same
tag with `releasenum` bumped, giving `X.Y.Z-2`. `tests/vercmp.sh` asserts all
of this in CI.

### Commit documentation separately

Documentation is `**.md` and `docs/**`; everything else is code — **including
comments inside `rpm/`, `build/`, `tests/` and `.github/`**, because the
packaging half of the version is keyed on those paths. A comment-only edit
there mints a new NEVRA for a byte-identical package.

The build skips only when the *whole push* is documentation (GitHub matches
`paths-ignore` per push, not per commit), so splitting commits does not by
itself save a build — but split them anyway: it keeps history revertable and
makes a free docs-only push possible.

`rpm/baseversion` exists because upstream's `include/version.h` records the
*last released* version (`4.3.30`, set in 2019), not what `main` is becoming;
it goes away if upstream starts bumping `version.h`.

## Retention

The stable channel keeps everything forever — people pin versions and roll
back. The snapshot channel keeps the newest **10 upstream commits** per
directory, and of each only its newest packaging rebuild, to stay within
GitHub Pages limits; the **build** workflow can override the number for one
run with `snapshot_keep`, or republish the channel from that run alone with
`snapshot_reset`.

Counting upstream commits rather than published runs is what makes those slots
worth having. Rolling back on a snapshot channel means going back to a different
state of Xymon, and an older packaging of the state you already have is not
that — so a morning of packaging merges can no longer spend every slot on one
upstream commit.

Pruning removes whole builds, never single packages — every package of a build
goes together, or the repo resolves to a missing dependency — and each removal
is named in the publish log, with which of the two rules dropped it.

## Known gaps

Runtime shortfalls waiting on upstream. This is one half of the ledger: the
build and install gaps this packaging compensates for, each with the upstream
pull request that would let the spec drop its workaround, are in
[docs/upstream.md](docs/upstream.md) *Gaps sent back upstream*.

- **The preprocessor channel is still dropped** — `CPPFLAGS`, where Debian's
  `dpkg-buildflags` ships `_FORTIFY_SOURCE`. Fedora and EL fold FORTIFY into
  `CFLAGS`, so RPM builds are covered and this is a Debian gap, tracked in
  [xymon#444](https://github.com/xymon-monitoring/xymon/issues/444). The RPM
  half closed with
  [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163): the
  makefiles take environment `CFLAGS` with `?=` and carry `$(LDFLAGS)` into
  all 92 link rules, so the spec passes `%{optflags}` and `%{build_ldflags}`
  and no longer needs the `-no-pie` that undid the asymmetry.
- `xymon-tmpfiles.conf` creates `/run/xymon`, which nothing uses yet: the
  pidfiles and control sockets that would fill it arrive with xymon#172 (the
  next gap), stacked on this one — the two land together,
  `xymon#219 → xymon#172`.
  [xymon#219](https://github.com/xymon-monitoring/xymon/pull/219) adds
  `XYMONRUNDIR` but defaults it to `$XYMONLOGDIR`, so the spec must also pass
  `XYMONRUNDIR=/run/xymon` — and ship the tmpfiles snippet in the client
  package, which currently lacks it. xymon#219 is rebased on current `main`,
  reviewed and CI-green, in draft.
- `ExecReload` sends `SIGHUP`, which `xymonlaunch` acts on itself but does not
  relay to its children until
  [xymon#172](https://github.com/xymon-monitoring/xymon/pull/172), so use
  `systemctl restart` to reach the daemons; the logrotate `copytruncate` sits
  behind the same gate. xymon#172 (stacked on xymon#219) is likewise rebased
  and CI-green, in draft.
- The SELinux modules build with `--with selinux` (`targeted`, `mls`,
  `minimum`) but are **off by default**: nothing in CI runs enforcing, so a
  green build only proves they compile — and their rules still reference
  `/var/cache/xymon`, which this layout does not use. Independently, `%post`
  labels the CGI and www paths when `semanage` is present. How to build,
  load and validate the modules is in [docs/selinux.md](docs/selinux.md).
- `XYMONSERVERHOSTNAME` is baked as `localhost` and rewritten from `uname -n`
  in `%post`, because a package must not carry the build host's name.

## Testing

How the suites are layered and how to run one is in [docs/testing.md](docs/testing.md); the full pipeline is in [docs/build-pipeline.md](docs/build-pipeline.md).


Every build runs `rpmspec -P` (a lua scriptlet with a `#` comment fails the
spec parse) and four suites over the built rpms:

| | |
| --- | --- |
| `vercmp.sh` | the version ordering above |
| `packages.sh` | the `Conflicts`, one byte-identical unit name in both packages, each role owning only its drop-in, no config under `/usr`, the client tree identical in both |
| `install.sh` | installs the client alone, proves `dnf install xymon` fails on the conflict, promotes and demotes, then serves the URLs — static content through its symlinks, a 404 for a missing file, the secure CGI answering 401 |
| `publish.sh` | publishes into a temporary tree with a throwaway key: the stable channel usable before its first release, a NEVRA never overwritten, retention dropping whole builds, a reset sparing stable |

Three more run on one EL and one Fedora target. Publishing waits on all of
them, and on the `lint` job:

| | |
| --- | --- |
| `systemd.sh` | under a real init (the only place scriptlets test, since without PID 1 every `systemctl` is swallowed by `\|\| :`) — enablement, both swap directions, drop-ins and teardown |
| `upgrade.sh` | installs the published build, seeds admin state, upgrades to this one and proves nothing was lost — the only suite starting from a non-empty root, so the only one exercising `%pretrans` |
| `monitoring.sh` | starts a server, lets its own client report, and asserts the data is analysed into `cpu`, `disk`, `memory` and `procs` — with the board checked *before* any client runs, so a query that always returns something cannot pass |

The last one earned its place immediately: a fresh install shipped `hosts.cfg`
naming `localhost` while the server's own client reported under `uname -n`, and
`xymond_client` silently discards a report whose host it cannot find. The host
stayed green from the network tests while no threshold was ever evaluated.

One more runs on a schedule rather than against a build. `docs.sh` checks that
[docs/upstream.md](docs/upstream.md) still matches the source — the PR table's
states, that every file its provenance table calls copied from `devel` still
compares equal, and that the PRs named order-independent are exactly the open
ones. It reports drift without gating publishing: a stale sentence is worth a
red run, not a held release. Separately, the build workflow rebuilds `main`
nightly as an upstream drift detector — a moved install path or configure flag
goes red the next day rather than at the next release.

## Building a branch or a pull request

Actions → **build** → *Run workflow* with a ref: `main` (default), `devel`,
`pr/163`, or any sha or tag. Only `main` and dispatched `rel-*` tags publish
(a tag build is the release flow); everything else produces downloadable
artifacts only. The run logs the exact commit built. The `releasenum` input
re-releases a tag with packaging fixes (see Versioning).

## Building locally

```sh
dnf -y install rpm-build rpmdevtools dnf-plugins-core
# On EL, rrdtool-devel and c-ares-devel need EPEL and CRB:
dnf -y install epel-release && dnf config-manager --set-enabled crb
rpmdev-setuptree
git clone https://github.com/xymon-monitoring/xymon.git src
git -C src archive --format=tar --prefix=xymon-4.3.31/ HEAD \
  | gzip -9 > ~/rpmbuild/SOURCES/xymon-4.3.31.tar.gz
cp rpm/sources/* ~/rpmbuild/SOURCES/
dnf -y builddep rpm/xymon.spec
rpmbuild -ba rpm/xymon.spec --define 'baseversion 4.3.31'
```

## Contributing

Changes go through a pull request. The rules are in
[CONTRIBUTING.md](CONTRIBUTING.md): which repository a change belongs in —
this one is not always the answer — how a title and a description are
written, when a change may merge without a review, and what counts as saying
how you tested it. [AGENTS.md](AGENTS.md) adds what a coding agent needs on
top of those, and `CLAUDE.md` imports it for Claude Code.

## Relationship to upstream

Packaging lives here so it can iterate without a review round per change; the
intent is to move it into `xymon-monitoring/xymon` once the spec is stable.
What `rpm/sources/` contains and why, the upstream PRs that would let the spec
drop its workarounds, and that plan in full are in
[docs/upstream.md](docs/upstream.md). Which of the two repositories a given
change belongs to is the first thing [CONTRIBUTING.md](CONTRIBUTING.md)
settles.

## License

GPL-2.0-only, matching Xymon.
