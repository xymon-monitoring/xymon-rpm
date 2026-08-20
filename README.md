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
| `xymon-devel` | headers and static libraries for building modules |
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

Demoting also needs `XYMSRV` set afterwards, and a host installed
before the packages conflicted needs the same swap before `dnf upgrade`
will resolve at all. Both, plus where every file lives and the everyday
admin tasks, are in [docs/admin-guide.md](docs/admin-guide.md).

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
Stream previews the next RHEL minor, so it is a canary — allowed to fail,
never published — alongside rawhide. Images are pinned, never floating: a
moving tag would silently change the dist tag and the published
repository path. Fedora is carried at N and N-1 and retired at EOL.

## Layout

```
rpm/xymon.spec      the spec; no patches
rpm/baseversion     the version main is working toward (see Versioning)
rpm/sources/        runtime integration files (units, init, logrotate, ...)
rpm/terabithia/     archived reference material, not built
build/publish.sh    signs packages and folds them into the published tree
build/mkrepofile.sh generates the .repo users install
docs/signing.md     how to create and install the signing key
docs/admin-guide.md where files are installed, and the everyday admin tasks
docs/deployment-strategies.md  how Debian, Terabithia, FreeBSD and this repo split server and client
tests/vercmp.sh     asserts the snapshot/release version ordering
tests/packages.sh   reads the built rpms: conflict, shared unit, role parity
tests/install.sh    installs the built packages and checks the scriptlets
tests/systemd.sh    role changes against a live systemd (privileged container)
```

## Versioning

Two channels, and they must sort correctly or dnf does the wrong thing
silently.

| Built from | Version | Release |
| --- | --- | --- |
| tag `rel-X.Y.Z` | `X.Y.Z` | `<n>%{?dist}`, default `1` |
| `main` | contents of `rpm/baseversion` | `0.<date>git<sha>.<pkgdate>p<pkgsha>%{?dist}` |

A snapshot is a *pre-release of the next version* (its `Release` starts
with `0.`), naming first the upstream commit and then the commit of this
repository. The second pair exists because a published NEVRA is
immutable: without it, a packaging-only fix rebuilds the same NEVRA and
is never published until upstream happens to move. The packaging datetime
(UTC) does the ordering, and a digit segment outranks the dist tag, so
extended builds also upgrade over ones published before the format
existed.

```
4.3.30-1
 -> 4.3.31-0.20260730git3a07523.202607301210pab12cd3   upgrade
 -> 4.3.31-0.20260731gitdeadbee.202607301210pab12cd3   upgrade (upstream moved)
 -> 4.3.31-0.20260731gitdeadbee.202608011535p9f8e7d6   upgrade (packaging moved)
 -> 4.3.31-1                                           upgrade (release lands)
```

Snapshot users are therefore absorbed into the stable channel when the
release lands. A packaging-only fix to a *released* version ships by
re-dispatching the same tag with the `releasenum` input bumped, producing
`X.Y.Z-2`. `tests/vercmp.sh` asserts all of this in CI.

`rpm/baseversion` exists because upstream's `include/version.h` records
the *last released* version (`4.3.30`, set in 2019), not the one `main`
is becoming; if upstream starts bumping `version.h` per cycle, the file
goes away.

## Retention

The stable channel keeps everything forever — people pin versions and
roll back. The snapshot channel keeps the newest **5 builds** per
directory (`XYMON_SNAPSHOT_KEEP` overrides) so the tree stays within
GitHub Pages limits. Pruning removes whole builds, never single packages
— rebuilds of one upstream commit count as one build — and every removal
is named in the publish log.

## Where the files in `rpm/sources/` come from

Xymon's systemd, init, logrotate and SELinux integration files were
written by J.C. Cleaver and live on the upstream `devel` (4.4) branch,
not in `main`; PR
[xymon#46](https://github.com/xymon-monitoring/xymon/pull/46) proposes to
bring them over. Until it merges they are vendored here:

| File | Taken from | Why |
| --- | --- | --- |
| `xymon.server-init`, `xymon.client-init` | Terabithia 4.3.30 SRPM | the `devel` copies pass `xymoncmd --no-env`, which does not exist in `main` until the `lib/stdopt.c` rework ([xymon#106](https://github.com/xymon-monitoring/xymon/issues/106)); they switch back to the `devel` copies when it lands |
| `xymon.logrotate` | adapted here | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay ([xymon#172](https://github.com/xymon-monitoring/xymon/pull/172)); `copytruncate` until it does |
| `xymon-client.default` | adapted here | the `devel` copy documents `XYMONSERVERS`, which only patched clients read; on `main` the server address lives in `xymonclient.cfg`, and the file now says so |
| `xymonlaunch.service`, `xymonlaunch-run` | written here (unit started from Terabithia's) | ONE unit for both roles, shipped by both packages; `xymonlaunch-run` picks the server tree when installed, else runs the client in the foreground (upstream's `runclient.sh` starts `xymonlaunch` without `--no-daemon`, so it forks and the script exits, leaving a `Type=simple` unit nothing to supervise) |
| everything else | upstream `devel` via PR #46 | identical in both, or 4.4-neutral |

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
- `xymon-tmpfiles.conf` creates `/run/xymon`, unused until `XYMONRUNDIR`
  arrives with [xymon#219](https://github.com/xymon-monitoring/xymon/pull/219).
- `ExecReload` sends `SIGHUP`, which `xymonlaunch` does not relay to its
  children until [xymon#172](https://github.com/xymon-monitoring/xymon/pull/172);
  use `systemctl restart`. The logrotate `copytruncate` sits behind the
  same gate.
- The SELinux modules build with `--with selinux` (`targeted`, `mls`,
  `minimum`) but are **off by default**: nothing in CI runs enforcing
  SELinux, so a green build only proves they compile — and their rules
  still reference `/var/cache/xymon`, which this layout does not use.
  Turning them on wants verification on an enforcing machine first.
  Independently of the modules, `%post` labels the CGI and www paths
  (`httpd_sys_script_exec_t` etc.) when `semanage` is present, since the
  default policy knows nothing about `/usr/lib/xymon` — that part, too,
  is asserted only as far as a non-enforcing container can.
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
`dnf install xymon` there fails on the conflict, then promotes and
demotes.

One EL and one Fedora target then run `tests/systemd.sh` under a real
init — the only place scriptlets can be tested at all, since without
PID 1 every `systemctl` in them is swallowed by `|| :`. It covers
enablement, both swap directions, the per-role drop-ins and teardown.
Publishing waits on it.

Not covered: upgrades from a previously published layout, since a
fixture of the old layout would have to be published first. The
`%pretrans` migrations are verified by hand.

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
