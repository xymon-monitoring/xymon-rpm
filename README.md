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
# EL only: the server pulls fping, which is in EPEL and in no RHEL
# repository -- not base, not CRB. Fedora carries fping in base, and the
# client package needs it on neither.
dnf install epel-release

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

**There has been no release yet**, so the stable channel is an empty
repository and `dnf install xymon` finds nothing in it. Until the first
`rel-*` tag, enable the snapshot channel above and install from there.

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
docs/               admin-guide, deployment-strategies, upstream, signing
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

Documentation is `**.md` and `docs/**`; everything else is code,
**including comments inside `rpm/`, `build/`, `tests/` and `.github/`**,
because the packaging half of the version is keyed on those paths. A
comment-only edit there mints a new NEVRA for a byte-identical package
and spends a snapshot retention slot.

The build skips only when the *whole push* is documentation — GitHub
matches `paths-ignore` per push, not per commit — so splitting the
commits does not by itself save a build. Split them anyway: it keeps
history revertable, and it is what makes a free docs-only push
possible.

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

## Known gaps

- **No distribution hardening flags** (FORTIFY, stack-protector, PIE):
  Xymon's makefiles discard `CFLAGS` from both the command line and the
  environment. `LDFLAGS` survives, but only reaches the 15 link rules of
  91 that mention it — 13 in `xymond/`, one each in `xymongen/` and
  `xymonnet/`. That is enough to matter: the build passes `-no-pie` there
  or the link fails on an `R_X86_64_32` relocation on Fedora and EL10.
  The other 76 links never see it and succeed anyway, so the flag is not
  reaching most of what we ship.
  [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163) fixes
  the `CFLAGS` root cause; the patchy `LDFLAGS` coverage is a separate
  gap nobody has raised upstream.
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
the whole spec parse) and four suites over the built rpms:

| | |
| --- | --- |
| `vercmp.sh` | the version ordering above |
| `packages.sh` | the `Conflicts`, one unit name byte-identical in both packages, each role owning only its drop-in, no configuration under `/usr`, the client tree identical in both |
| `install.sh` | installs the client alone, proves `dnf install xymon` there fails on the conflict, promotes and demotes, then serves the URLs — static content through its symlinks, a missing file that must be 404 rather than a denial, the secure CGI answering 401 |
| `publish.sh` | publishes into a temporary tree with a throwaway key, never the real repository: the stable channel usable before its first release, a published NEVRA never overwritten, retention dropping whole builds and naming them, a reset sparing the stable channel |

Three more run on one EL and one Fedora target, and publishing waits on
all of them:

| | |
| --- | --- |
| `systemd.sh` | under a real init — the only place scriptlets can be tested, since without PID 1 every `systemctl` in them is swallowed by `\|\| :` — covering enablement, both swap directions, the drop-ins and teardown |
| `upgrade.sh` | installs the published build, seeds admin state, upgrades to this one and proves nothing was lost. The only suite starting from a non-empty root, so the only one exercising `%pretrans`; its fixture is whatever is published, so a layout change is exercised by the push after it |
| `monitoring.sh` | starts a server, lets its own client report, and asserts the data is analysed into `cpu`, `disk`, `memory` and `procs` — with the board checked *before* any client runs, so a query that always returns something cannot pass |

The last one earned its place immediately: a fresh install shipped
`hosts.cfg` naming `localhost` while the server's own client reported
under `uname -n`, and `xymond_client` discards a report whose host it
cannot find without logging anything. The host stayed green from the
network tests while no threshold was ever evaluated, and every other
suite passed.

One more runs on a schedule rather than against a build. `docs.sh` checks
that [docs/upstream.md](docs/upstream.md) still matches the source: that
the pull request table's states are the real ones, that every file its
provenance table calls copied from `devel` still compares equal to it,
and that the PRs named as order-independent are exactly the open ones.
Those claims go stale when something changes upstream, which no push here
would ever notice. It reports drift without gating publishing — a stale
sentence is worth a red run, not a held release.

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

Packaging lives here so it can iterate without a review round per
change; the intent is to move it into `xymon-monitoring/xymon` once the
spec is stable. What `rpm/sources/` contains and why, the upstream PRs
that would let the spec drop its workarounds, and that plan in full are
in [docs/upstream.md](docs/upstream.md).

## License

GPL-2.0-only, matching Xymon.
