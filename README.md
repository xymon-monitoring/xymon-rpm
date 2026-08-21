# Xymon RPM packages

Official RPM packaging for [Xymon](https://github.com/xymon-monitoring/xymon),
built from the upstream source tree with **no source patches** — the spec
has zero `Patch:` lines. Anything that needs changing in Xymon itself is
fixed upstream, not here.

> [!WARNING]
> **Highly experimental.** This packaging is new and has seen no
> production use. Package layout, versioning, and the published
> repository structure may still change without notice — do not point
> production machines at it yet.

## Packages

| Package | Contents |
| --- | --- |
| `xymon` | the server, including the client component it runs on itself |
| `xymon-client` | the same client packaged alone, for every host that is not the server |
| `xymon-client-local` | xymond_client on a client, for local threshold analysis |
| `xymon-devel` | headers and static libraries for building modules (pulls in `pcre2-devel`, which its headers include) |
| `xymon-tools` | diagnostics: stackio, locator, tree, availability, loadhosts |

`xymon` and `xymon-client` **conflict**: a host is a server or a client,
never both. See
[docs/deployment-strategies.md](docs/deployment-strategies.md) for why —
and for how Debian, Terabithia and FreeBSD packaged the same split.

`xymon-devel` and `xymon-tools` exist because Xymon's own build discards
both: `make install` places no headers or libraries, and `lib/` has no
install rule for the tools it builds.

## Installing

```sh
curl -o /etc/yum.repos.d/xymon.repo \
  https://xymon-monitoring.github.io/xymon-rpm/xymon.repo
dnf install xymon          # server
dnf install xymon-client   # client only
```

Every host runs the same single unit, `xymonlaunch.service`; it picks
the server or the client role by which package is installed. A
client-only host sets the server address (`XYMSRV`) in
`/etc/xymon-client/xymonclient.cfg` and runs
`systemctl enable --now xymonlaunch`. Installing the server on a client
host fails on the package conflict — by design. Changing a host's role
is one transaction:

```sh
dnf swap xymon-client xymon     # promote a client to the server
dnf swap xymon xymon-client     # demote a server to a client
systemctl restart xymonlaunch   # the swap stops the old role cleanly
                                # but starts nothing; this brings the
                                # new one up
```

Demoting also needs `XYMSRV` set afterwards, and a host installed before
the packages conflicted needs the same swap before `dnf upgrade` will
resolve at all. Both, plus where every file lives and the everyday admin
tasks, are in [docs/admin-guide.md](docs/admin-guide.md).

Packages and repository metadata are signed; verify the key against this
fingerprint (see [docs/signing.md](docs/signing.md)):

```
Xymon Project (RPM signing key)
BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

Snapshots built from `main` are in the same file but disabled; enable per
host with `dnf config-manager --set-enabled xymon-snapshot`.

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

EL builds run on AlmaLinux, a rebuild of *released* RHEL, so they cannot
need a symbol version RHEL lacks; the dist tag carries no vendor marker,
so an `.el8` package runs on RHEL, Rocky, Oracle and Alma alike. CentOS
Stream previews the next RHEL minor, so it is a canary alongside
rawhide — allowed to fail, never published. Images are pinned: a moving
tag would silently change the dist tag and the published path. Fedora is
carried at N and N-1.

## Layout

```
rpm/xymon.spec      the spec; no patches
rpm/baseversion     the version main is working toward (see Versioning)
rpm/sources/        runtime integration (unit, drop-ins, logrotate, sysusers, ...)
rpm/terabithia/     archived reference material, not built
build/               publish.sh signs and folds packages into the published
                     tree; mkrepofile.sh and mkindex.sh generate the .repo
                     file and the browsable index
docs/               signing.md, admin-guide.md, deployment-strategies.md
tests/              see Testing
```

## Versioning

Two channels, and they must sort correctly or dnf does the wrong thing
silently.

| Built from | Version | Release |
| --- | --- | --- |
| tag `rel-X.Y.Z` | `X.Y.Z` | `<n>%{?dist}`, default `1` |
| `main` | contents of `rpm/baseversion` | `0.<date>git<sha>.<pkgdate>p<pkgsha>%{?dist}` |

A snapshot is a *pre-release of the next version* (its `Release` starts
with `0.`), naming the upstream commit and then the last commit here
that could change a package — one touching `rpm/`, `build/` or
`.github/`. The second pair exists because a published NEVRA is
immutable: without it a packaging-only fix rebuilds the same NEVRA and
never ships until upstream happens to move. Keying it on `HEAD` instead
would mint a new NEVRA for every documentation commit, so docs-only
pushes skip the build entirely. The packaging datetime (UTC) does the
ordering, and a digit segment outranks the dist tag, so extended builds
also upgrade over ones published before the format existed.

```
4.3.30-1
 -> 4.3.31-0.20260730git3a07523.202607301210pab12cd3   upgrade
 -> 4.3.31-0.20260731gitdeadbee.202607301210pab12cd3   upgrade (upstream moved)
 -> 4.3.31-0.20260731gitdeadbee.202608011535p9f8e7d6   upgrade (packaging moved)
 -> 4.3.31-1                                           upgrade (release lands)
```

Snapshot users are therefore absorbed into the stable channel when the
release lands. A packaging-only fix to a *released* version ships by
re-dispatching the same tag with `releasenum` bumped, giving `X.Y.Z-2`.
`tests/vercmp.sh` asserts all of this in CI.

### Commit documentation separately

Documentation is `**.md` and `docs/**`. Everything else is code —
**including comments inside `rpm/`, `build/`, `tests/` and `.github/`**,
because the packaging half of the version is keyed on those paths. A
comment-only edit there still mints a new NEVRA for a byte-identical
package, and publishing it costs a slot in the five-build snapshot
retention window.

So keep the two in separate commits. The build only skips when the
*push* is documentation alone — GitHub matches `paths-ignore` against
everything in the push, not commit by commit — so a docs-only change is
free, while a mixed push builds once whether or not the commits were
split. Split them anyway: it keeps history revertable, and it makes the
free case possible.

`rpm/baseversion` exists because upstream's `include/version.h` records
the *last released* version (`4.3.30`, set in 2019), not the one `main`
is becoming; it goes away if upstream starts bumping `version.h`.

## Retention

The stable channel keeps everything forever — people pin versions and
roll back. The snapshot channel keeps the newest **5 builds** per
directory so the tree stays within GitHub Pages limits; the **build**
workflow can override that for one run with `snapshot_keep`, or
republish the channel from that run alone with `snapshot_reset`.

Pruning removes whole builds, never single packages — every package of a
build goes together, or the repository resolves to a missing dependency
— and each removal is named in the publish log. A build is one
*published run*, packaging rebuilds included: while upstream sits still,
packaging changes would otherwise pile up inside one upstream commit
forever, which no retention count could trim.

## Where the files in `rpm/sources/` come from

Upstream `main` ships no systemd, logrotate or SELinux integration at
all — those live on the `devel` (4.4) branch, written by J.C. Cleaver.
Everything needed to package for a systemd distribution is therefore
written or adapted here. Nothing in this repository waits on an upstream
merge to work.

| File | Origin | Why |
| --- | --- | --- |
| `xymonlaunch.service`, `xymonlaunch-run`, `xymonlaunch-server.conf`, `xymonlaunch-client.conf` | written here | ONE unit for both roles, shipped by both packages; `xymonlaunch-run` picks the tree by which role's drop-in is installed and runs `xymoncmd xymonlaunch --no-daemon` for either. Upstream's own `runclient.sh` and `xymon.sh` both fork and exit, leaving a `Type=simple` unit nothing to supervise; `xymoncmd` avoids them entirely and supplies the environment itself |
| `xymonlaunch.service.preset` | written here | one line, and deliberately server-only: a fresh client must not enable itself against the baked-in `XYMSRV` |
| `xymon.sysusers` | written here | [xymon#413](https://github.com/xymon-monitoring/xymon/pull/413) proposes it upstream |
| `xymon-tmpfiles.conf` | written here | creates `/run/xymon`, which nothing uses yet (see Known gaps) |
| `xymon-sysctl.conf` | adapted from `devel` | the backfeed-queue tunables; `main` has no equivalent |
| `xymon.logrotate` | adapted from `devel` | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay ([xymon#172](https://github.com/xymon-monitoring/xymon/pull/172)); `copytruncate` until it does |
| `xymon-client.default`, `xymonlaunch.default` | adapted from `devel` | they document `XYMONSERVERS`, which only patched clients read, and name this packaging's own config paths |
| `xymon.te`, `xymon-client.te`, `bb.xml` | copied from `devel` | reference material, shipped as `%doc` only — the policy modules are not compiled by default (see Known gaps) |

The upstream gaps these work around are proposed as small PRs rather
than waited on — each lands a feature that lets this spec delete a
workaround:

| PR | What it adds | |
| --- | --- | --- |
| [#410](https://github.com/xymon-monitoring/xymon/pull/410) | installs libraries and headers | open |
| [#411](https://github.com/xymon-monitoring/xymon/pull/411) | `INSTALLCLIENT*DIR` | open |
| [#414](https://github.com/xymon-monitoring/xymon/pull/414) | `INSTALLSTATICWWWDIR` | open |
| [#409](https://github.com/xymon-monitoring/xymon/pull/409) | installs the `lib/` diagnostics | draft |
| [#412](https://github.com/xymon-monitoring/xymon/pull/412) | `INSTALLHTTPDCONFDIR` | draft |
| [#413](https://github.com/xymon-monitoring/xymon/pull/413) | a `sysusers.d` snippet | draft |

They merge independently in any order — checked across all 5040
orderings (with [#408](https://github.com/xymon-monitoring/xymon/pull/408),
since withdrawn: `xymoncmd` already runs the client in the foreground,
so the packaging needed nothing). All but #410 are no-ops until their variable is set; #410 adds
`install-libs` to the server's default `INSTALLTARGETS`, so a plain
`make install` gains the libraries and headers (raised with the
maintainer on the PR, since #409 gates the same kind of addition and the
two should agree). Only #413 is systemd-specific; the rest are plain make
and POSIX shell, verified on Debian as well as EL.

The three drafts are parked, not abandoned: each replaces a workaround
that costs this spec one `mv` or three lines of `%install`, which is not
enough to spend upstream review on. The three still open each delete
something Debian carries by hand too — `debian/rules` does #411's three
symlinks at lines 96-98 and #414's three at 72-74.

`rpm/terabithia/` archives the reference spec and README from
<https://repo.terabithia.org/rpms/xymon/> — a single unmirrored host —
for provenance only; it is never built.

## Known gaps

- **No distribution hardening flags** (FORTIFY, stack-protector, PIE):
  Xymon's makefiles discard `CFLAGS` from both the command line and the
  environment, and because `LDFLAGS` *is* honoured, the build must pass
  `-no-pie` on Fedora and EL10 or the link fails on an `R_X86_64_32`
  relocation. [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163)
  fixes the root cause; merging it removes both workarounds.
- `xymon-tmpfiles.conf` creates `/run/xymon`, which nothing uses.
  [xymon#219](https://github.com/xymon-monitoring/xymon/pull/219) adds
  `XYMONRUNDIR` but defaults it to `$XYMONLOGDIR`, so merging it is not
  enough: the spec must pass `XYMONRUNDIR=/run/xymon` too. Whoever wires
  that up should also ship the tmpfiles snippet in the client package,
  which does not have it — a client-only host has no `/run/xymon` for
  its pidfiles.
- `ExecReload` sends `SIGHUP`, which `xymonlaunch` acts on itself
  (rereads `tasks.cfg`, reopens its log) but does not relay to its
  children until
  [xymon#172](https://github.com/xymon-monitoring/xymon/pull/172), so
  use `systemctl restart` to reach the daemons. The logrotate
  `copytruncate` sits behind the same gate. #172 is stacked on #219.
- The SELinux modules build with `--with selinux` (`targeted`, `mls`,
  `minimum`) but are **off by default**: nothing in CI runs enforcing, so
  a green build only proves they compile — and their rules still
  reference `/var/cache/xymon`, which this layout does not use.
  Independently of them, `%post` labels the CGI and www paths when
  `semanage` is present, since the default policy knows nothing about
  `/usr/lib/xymon`; that too is asserted only as far as a non-enforcing
  container can.
- `XYMONSERVERHOSTNAME` is baked as `localhost` and rewritten from
  `uname -n` in `%post`, because a package must not carry the build
  host's name.

## Testing

Every build runs `rpmspec -P` (a lua scriptlet with a `#` comment fails
the whole spec parse), `tests/vercmp.sh` for the version ordering above,
`tests/packages.sh` over the built rpms (the `Conflicts`, one unit name
byte-identical in both packages, each role owning only its drop-in, no
configuration under `/usr`, the shared client tree identical in both),
and `tests/install.sh`, which installs the client alone, proves
`dnf install xymon` there fails on the conflict, promotes and demotes,
then starts httpd and fetches the URLs — static content through its
symlinks, a missing file that must be 404 rather than a denial, and the
secure CGI path, which must answer 401.

One EL and one Fedora target run two more. `tests/systemd.sh` works
under a real init — the only place scriptlets can be tested at all,
since without PID 1 every `systemctl` in them is swallowed by `|| :` —
covering enablement, both swap directions, the drop-ins and teardown.
`tests/upgrade.sh` installs the build currently in the snapshot channel,
edits `XYMSRV`, adds a task, drops files into the web tree, upgrades to
the build under test and proves nothing was lost. It is the only suite
that starts from a non-empty root, and so the only one that exercises
`%pretrans`; since its fixture is whatever is published, a layout change
is exercised by the push after it. Publishing waits on both.

Not covered: that Xymon actually monitors anything. Every suite tests
packaging — files, units, scriptlets, upgrades — and none starts a
server and waits for data.

## Building a branch or a pull request

Actions → **build** → *Run workflow* with a ref: `main` (the default),
`devel`, `pr/163`, or any sha or tag. Only `main` and dispatched `rel-*`
tags publish — a tag build is the release flow — everything else produces
downloadable artifacts and nothing more. The run logs the exact commit it
built, since a pull request's head moves. The `releasenum` input
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

## Relationship to upstream

Packaging lives here so it can iterate without a review round per change.
Once the spec is stable, the intent is to move it and the build workflow
into `xymon-monitoring/xymon` — the convention Debian packaging follows —
leaving this repository as the publishing target. The nightly build
doubles as a drift detector: an upstream change that moves an install
path or a configure flag goes red here the next day.

## License

GPL-2.0-only, matching Xymon.
