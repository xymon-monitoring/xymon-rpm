# Xymon RPM packages

Official RPM packaging for [Xymon](https://github.com/xymon-monitoring/xymon).

This repository builds Xymon from the upstream source tree. It carries **no
source patches** — the spec applies zero `Patch:` lines. Anything that needs
changing in Xymon itself is fixed upstream, not here.

## Status

Building green on every target below, signed and published from `main`.

## Packages

| Package | Contents |
| --- | --- |
| `xymon` | the server |
| `xymon-client` | client-side data collection; self-contained, with its own `xymon-client.service` |
| `xymon-client-local` | xymond_client on a client, for local threshold analysis |
| `xymon-devel` | headers and static libraries for building modules |
| `xymon-tools` | diagnostic programs: stackio, locator, tree, availability, loadhosts |

`xymon-devel` and `xymon-tools` exist because Xymon's build discards both:
`make install` places no headers or static libraries anywhere, and `lib/`
has no install rule at all, so the five tools its `all` target builds are
thrown away with the build tree.

## Installing

```sh
curl -o /etc/yum.repos.d/xymon.repo \
  https://xymon-monitoring.github.io/xymon-rpm/xymon.repo
dnf install xymon          # server
dnf install xymon-client   # client only
```

A server runs `xymonlaunch.service`, which supervises everything --
including the client's tasks, through `tasks.cfg`. A client-only host
sets the server's address (`XYMSRV`) in
`/usr/lib/xymon/client/etc/xymonclient.cfg` and runs

```sh
systemctl enable --now xymon-client
```

The two units conflict on purpose: running both on a server would report
duplicate client data.

Packages and repository metadata are signed. Verify the key you receive
against the fingerprint published here:

```
Xymon Project (RPM signing key)
BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

See [docs/signing.md](docs/signing.md).

Development snapshots built from `main` are in the same file but disabled;
enable them per host with
`dnf config-manager --set-enabled xymon-snapshot`.

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

Published EL builds run on AlmaLinux, a rebuild of *released* RHEL, so
they cannot link against a symbol version RHEL does not ship. CentOS
Stream is the development branch for the next RHEL minor, which risks a
package that installs on Stream and fails on RHEL — so Stream is carried
as a canary instead, alongside Fedora rawhide. Canaries are allowed to
fail and are never published.

A package built on any EL8 rebuild runs on RHEL 8, Rocky 8, Oracle Linux
8, CentOS Stream 8 and AlmaLinux 8 alike; the dist tag is plain `.el8`,
with no vendor marker.

Images are pinned rather than floating: `fedora:latest` would silently
change the dist tag at each Fedora release and move the published
repository path with no commit to point at. Fedora is carried at N and
N-1 and retired at EOL, so the target list stays a statement of what is
supported rather than a record of what was once built.

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

A snapshot is a *pre-release of the next version*, so its `Release` starts
with `0.`. The first date/sha pair names the upstream commit; the second
names the commit of *this* repository, because a published NEVRA is
immutable — without it, a packaging-only fix rebuilds the same NEVRA as
the previous run and is never published until upstream happens to move.
The packaging datetime (UTC) does the ordering; rpm treats a digit
segment as newer than the dist tag's alpha segment, so the extended form
also upgrades over unextended builds published before it existed.

```
4.3.30-1
 -> 4.3.31-0.20260730git3a07523.202607301210pab12cd3   upgrade
 -> 4.3.31-0.20260731gitdeadbee.202607301210pab12cd3   upgrade (upstream moved)
 -> 4.3.31-0.20260731gitdeadbee.202608011535p9f8e7d6   upgrade (packaging moved)
 -> 4.3.31-1                                           upgrade (release lands)
```

A snapshot user is therefore absorbed into the stable channel when the
release lands, rather than being stranded above it. `tests/vercmp.sh`
asserts all of this in CI.

Stable builds get the same treatment as snapshots when packaging alone
changes: rebuilding `X.Y.Z-1` would collide with the published NEVRA and
be refused, so a packaging-only fix to a released version is shipped by
re-dispatching a build of the same tag with the `releasenum` input
bumped, producing `X.Y.Z-2`.

`rpm/baseversion` exists because upstream's `include/version.h` records the
*last released* version (`4.3.30`, set in 2019), not the one `main` is
becoming. If upstream starts bumping `version.h` at the opening of each
development cycle, this file goes away and the spec reads `version.h`
directly.

## Retention

The stable channel keeps every package forever. People pin versions and
roll back, so removing a published release breaks them.

The snapshot channel keeps the newest **5 builds** per release and
architecture, and prunes older ones on each publish; set
`XYMON_SNAPSHOT_KEEP` to change it. Snapshots are pre-releases of an
untested version, shipped disabled by default, so they are disposable —
and without pruning the published tree would grow without bound against
GitHub Pages' size and bandwidth limits.

Retention counts *builds*, not files. One build produces several packages,
and dropping only some of them would leave a repository that resolves to a
missing dependency. Rebuilds of one upstream commit under different
packaging commits count as a single build, kept and pruned as a unit. Anything removed is named in the publish log rather
than dropped silently.

## Where the files in `rpm/sources/` come from

Xymon's systemd, init, logrotate and SELinux integration files were written
by J.C. Cleaver and live on the upstream `devel` (4.4) branch. They are not
in `main`; PR [xymon#46](https://github.com/xymon-monitoring/xymon/pull/46)
proposes to bring them over. Until it merges they are vendored here.

Three of them differ between the 4.4 branch and the 4.3.x line, and the
4.3.x form is the correct one for a build from `main`; the rest of the
table is adapted or written here:

| File | Taken from | Why |
| --- | --- | --- |
| `xymonlaunch.service` | Terabithia 4.3.30 SRPM | the `devel` copy passes `xymoncmd --no-env`, and `--no-env` does not exist in `main` — it arrives with the `lib/stdopt.c` rework tracked in [xymon#106](https://github.com/xymon-monitoring/xymon/issues/106) |
| `xymon.server-init` | Terabithia 4.3.30 SRPM | same |
| `xymon.client-init` | Terabithia 4.3.30 SRPM | same |
| `xymon.logrotate` | adapted here | the `devel` copy's postrotate sends `SIGHUP` to `xymonlaunch`, which `main` does not relay to its children ([xymon#172](https://github.com/xymon-monitoring/xymon/pull/172)), and no init script is shipped that could reopen the logs — so the fragment uses `copytruncate` instead |
| `xymon-client.service`, `xymonclient-run` | written here | upstream has no client unit: its `runclient.sh` backgrounds `xymonlaunch`, which systemd cannot supervise, so `xymonclient-run` reproduces that script's environment in the foreground; `xymonlaunch.service`'s upstream `Alias=xymon-client.service` is dropped so the alias cannot shadow the real unit |
| everything else | upstream `devel` via PR #46 | identical in both, or 4.4-neutral |

When the `stdopt` group lands in `main`, those three switch back to the
`devel` copies.

`rpm/terabithia/` archives the reference spec and README from
<https://repo.terabithia.org/rpms/xymon/>, which is a single unmirrored host.
It is kept for provenance and is never built.

## Known gaps

- The packages carry **no distribution hardening flags** (FORTIFY,
  stack-protector, PIE). There is currently no way to inject them: on the
  make command line a `CFLAGS=` assignment overrides `lib/Makefile`'s
  `CFLAGS += -I../include` and the build cannot find its own headers, and
  via the environment `build/Makefile.Linux` discards `CFLAGS` with a plain
  `=`. Because `LDFLAGS` *is* honoured, the build additionally has to pass
  `-no-pie` on Fedora and EL10, whose gcc defaults to PIE, or the link fails
  on an `R_X86_64_32` relocation against non-PIC objects.
  [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163) fixes the
  root cause in three lines; merging it removes both workarounds.

- `xymon-tmpfiles.conf` creates `/run/xymon`, but `main` has no
  `XYMONRUNDIR`, so the directory is currently unused. It becomes live when
  [xymon#219](https://github.com/xymon-monitoring/xymon/pull/219) merges.
- `ExecReload` sends `SIGHUP` to `xymonlaunch`, which does not yet relay it
  to its children on `main`. That arrives with
  [xymon#172](https://github.com/xymon-monitoring/xymon/pull/172). Use
  `systemctl restart` until then. The logrotate fragment sits behind the
  same gate: it uses `copytruncate` because no signal reopens the logs,
  and switches to the upstream postrotate form when #172 lands.
- The SELinux policy modules are wired up but **off by default**. Building
  with `--with selinux` compiles them for the `targeted`, `mls` and
  `minimum` variants and loads them with `semodule`, which is what the
  Terabithia packages ship. They are off here because nothing in CI runs
  enforcing SELinux, so a green build proves only that the policy compiles.
  The modules also predate the current layout: their comments reference
  `/var/cache/xymon` for `rep`/`snap`, which this packaging does not use,
  so those rules would be inert. Turning them on wants verification on an
  enforcing machine first.
- `XYMONSERVERHOSTNAME` is baked as `localhost` at build time and rewritten
  from `uname -n` in `%post`, because a package must not carry the build
  host's name. A runtime resolution upstream would make this unnecessary.

## Testing

Every build runs two checks:

- `tests/vercmp.sh` — asserts the snapshot/release ordering. A mistake
  there fails silently rather than failing a build, so it is asserted
  rather than assumed.
- `tests/install.sh` — installs the built packages and checks what a green
  `rpmbuild` cannot: that dependencies resolve, that `%pre` creates the
  account, that the unit's absolute paths resolve, that `systemd` accepts
  the unit, and that `%post` rewrote the baked-in `localhost` hostname.
  The client is installed *alone* first and checked before the rest is
  layered on top — installed together, the server package would mask
  everything a client-only host is missing.

Note that assertions are made against the package (`rpm -ql`) rather than
against paths on disk where possible: container images vary in what they
actually unpack, so a path probe can fail on a package that is correct.

The service itself is not started — containers have no running init.
`systemd-analyze verify` is the closest check available without PID 1.

## Building a branch or a pull request

Actions → **build** → *Run workflow*, and give a ref:

| Input | Builds |
| --- | --- |
| `main` | the default |
| `devel` | the 4.4 development branch |
| `pr/163` | pull request 163 in xymon-monitoring/xymon |
| any sha or tag | that exact commit |

Nothing is published: publishing only happens for `main`, so a branch or
pull request build produces downloadable artifacts and nothing else. Use it
to check that a change still packages and that the resulting RPM installs,
before merging it.

Because a pull request's head moves, the run logs the exact commit it
built, so an artifact can always be traced back to a specific revision.

## Building locally

```sh
dnf -y install rpm-build rpmdevtools dnf-plugins-core
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
Once the spec is stable the intent is to move `rpm/xymon.spec` and the build
workflow into `xymon-monitoring/xymon` — the same convention Debian
packaging follows — leaving this repository as the publishing target.

The nightly build against `main` doubles as a drift detector: if an upstream
change moves an install path or a configure flag, this repository goes red
the next day.

## License

GPL-2.0-only, matching Xymon.
