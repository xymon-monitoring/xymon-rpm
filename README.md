# Xymon RPM packages

Official RPM packaging for [Xymon](https://github.com/xymon-monitoring/xymon),
built from the upstream source tree with **no source patches** — the spec
has zero `Patch:` lines. Anything that needs changing in Xymon itself is
fixed upstream, not here.

## Packages

| Package | Contents |
| --- | --- |
| `xymon` | the server |
| `xymon-client` | client-side data collection; standalone, with its own `xymon-client.service` |
| `xymon-client-local` | xymond_client on a client, for local threshold analysis |
| `xymon-devel` | headers and static libraries for building modules |
| `xymon-tools` | diagnostics: stackio, locator, tree, availability, loadhosts |

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

A server runs `xymonlaunch.service`, which supervises everything — the
client's tasks included. A client-only host sets the server address
(`XYMSRV`) in `/usr/lib/xymon/client/etc/xymonclient.cfg` and runs
`systemctl enable --now xymon-client`. The two units conflict on purpose:
both at once would report duplicate client data.

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
tests/vercmp.sh     asserts the snapshot/release version ordering
tests/install.sh    installs the built packages and checks the scriptlets
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
| `xymonlaunch.service`, `xymon.server-init`, `xymon.client-init` | Terabithia 4.3.30 SRPM | the `devel` copies pass `xymoncmd --no-env`, which does not exist in `main` until the `lib/stdopt.c` rework ([xymon#106](https://github.com/xymon-monitoring/xymon/issues/106)); they switch back to the `devel` copies when it lands |
| `xymon.logrotate` | adapted here | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay ([xymon#172](https://github.com/xymon-monitoring/xymon/pull/172)); `copytruncate` until it does |
| `xymon-client.service`, `xymonclient-run` | written here | upstream has no client unit — its `runclient.sh` backgrounds `xymonlaunch`, which systemd cannot supervise — so `xymonclient-run` is its foreground equivalent; `xymonlaunch.service`'s upstream `Alias=xymon-client.service` is dropped so it cannot shadow the real unit |
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
- `XYMONSERVERHOSTNAME` is baked as `localhost` and rewritten from
  `uname -n` in `%post`, because a package must not carry the build
  host's name.

## Testing

Every build runs two checks:

- `tests/vercmp.sh` — asserts the version ordering above, which fails
  silently rather than failing a build when it breaks.
- `tests/install.sh` — installs the client *alone* first (together, the
  server would mask everything a client-only host is missing), then all
  packages, and checks what a green `rpmbuild` cannot: dependencies
  resolve, `%pre` creates the account, unit paths resolve,
  `systemd-analyze verify` accepts the units, and `%post` rewrote the
  baked-in `localhost` hostname. Services are not started — containers
  have no PID 1.

## Building a branch or a pull request

Actions → **build** → *Run workflow* with a ref: `main` (the default),
`devel`, `pr/163`, or any sha or tag. Nothing is published — only `main`
publishes — and the run logs the exact commit it built, since a pull
request's head moves. The `releasenum` input re-releases a tag with
packaging fixes (see Versioning).

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
