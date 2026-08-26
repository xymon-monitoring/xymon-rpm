# Upstream: what this packaging adds, and what it sends back

The spec builds the `xymon-monitoring/xymon` tree **with no patches at
all; fixes belong upstream.** This repository and that one are separate
on purpose: packaging iterates faster than a source tree can review it.
This file records what had to be written here because upstream has no
equivalent, and which of those gaps are being closed upstream so the
spec can delete its workaround.

## How the upstream ref is selected

The build clones `https://github.com/xymon-monitoring/xymon.git` and
checks out `XYMON_REF`, which the `workflow_dispatch` input `xymon_ref`
sets and which defaults to `main`. It accepts a branch, tag, sha, or a
pull request as `pr/NNN` (or `refs/pull/NNN/head`) — a PR ref is fetched
explicitly, since a plain clone does not carry `refs/pull/*`. The source
tarball is `git archive` of the checked-out `HEAD`, so no tree
modification ever happens between clone and build.

## Where the files in `rpm/sources/` come from

Upstream `main` ships no systemd or SELinux integration, and its two
logrotate files live only in its own unmaintained `rpm/` and `debian/`
packagings (described below). The `devel` (4.4) branch does carry `tools/xymonlaunch.service`,
its preset and `xymon-tmpfiles.conf` (written by J.C. Cleaver), but they
have never been merged to `main`. So the files below are adapted from
`devel` where one existed and written here where none did. Nothing in
this repository waits on an upstream merge to work.

That unmerged unit already wraps `xymoncmd` around `xymonlaunch
--no-daemon` — the same conclusion this packaging reached independently
by testing. [#415](https://github.com/xymon-monitoring/xymon/pull/415)
carries it to `main` with paths substituted from the build rather than
hardcoded, so it serves a source install and any packaging, not only RPM.

| File | Origin | Why | Upstream PR |
| --- | --- | --- | --- |
| `xymonlaunch.service` | adapted from `devel` | eleven directives are verbatim from `devel`'s `tools/xymonlaunch.service`, including the `xymoncmd` wrapping. Four things differ, all this packaging's: `ExecStart` calls `xymonlaunch-run` for role dispatch, the kill semantics move into the server's drop-in, `Alias=xymon-client.service` is dropped because one unit serves both roles, and the second `EnvironmentFile` is `/etc/sysconfig/xymon-client`. Once it lands, only those four differences remain | [#415](https://github.com/xymon-monitoring/xymon/pull/415) |
| `xymonlaunch-run`, `xymonlaunch-server.conf`, `xymonlaunch-client.conf` | written here | the role dispatch itself. `xymonlaunch-run` picks the tree by which role's drop-in is present and runs `xymoncmd xymonlaunch --no-daemon`; the drop-ins carry what differs. All three exist because these two packages conflict and share one unit | — packaging-only |
| `xymonlaunch.service.preset` | byte-identical to `devel`'s | one line, the same one. What is ours is shipping it *only* in the server package: a fresh client must not enable itself against the baked-in `XYMSRV` | [#415](https://github.com/xymon-monitoring/xymon/pull/415) |
| `xymon.sysusers` | written here | declares the `xymon` system user and group | [#413](https://github.com/xymon-monitoring/xymon/pull/413) |
| `xymon-tmpfiles.conf` | byte-identical to `devel`'s | creates `/run/xymon`, which nothing uses yet — until [xymon#219](https://github.com/xymon-monitoring/xymon/pull/219) points pidfiles and `rrd` control sockets there via `XYMONRUNDIR` (see the README's known gaps) | [#415](https://github.com/xymon-monitoring/xymon/pull/415) |
| `xymon-sysctl.conf` | byte-identical to `devel`'s | the backfeed-queue tunables; `main` has no equivalent | — none |
| `xymon.logrotate` | adapted from `devel` | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay yet; `copytruncate` until it does | [#172](https://github.com/xymon-monitoring/xymon/pull/172) (the `SENDHUP` enabler) |
| `xymon-client.default`, `xymonlaunch.default` | adapted from `devel` | both name this packaging's config paths instead of upstream's; `xymon-client.default` also documents `XYMONSERVERS`, which only patched clients read | [#415](https://github.com/xymon-monitoring/xymon/pull/415) (`xymonlaunch.default` only) |
| `xymon.te`, `xymon-client.te`, `bb.xml` | copied from `devel` | reference material, shipped as `%doc` by default and compiled to loadable modules only under `--with selinux` (see [docs/selinux.md](selinux.md)) | — `%doc` only |

## Gaps sent back upstream

Each is a feature this packaging proposed upstream — most let the spec
delete a hand-rolled workaround; one (#443) completes the `www` FHS story
ahead of the spec consuming it. They are proposed rather than waited on; a
proposal drops off this list once it merges.

| PR | What it adds | State |
| --- | --- | --- |
| [#409](https://github.com/xymon-monitoring/xymon/pull/409) | installs the `lib/` diagnostics | open |
| [#410](https://github.com/xymon-monitoring/xymon/pull/410) | `make install-devel` installs the libraries and headers | open |
| [#411](https://github.com/xymon-monitoring/xymon/pull/411) | `INSTALLCLIENT*DIR` | open |
| [#412](https://github.com/xymon-monitoring/xymon/pull/412) | `INSTALLHTTPDCONFDIR` | draft |
| [#413](https://github.com/xymon-monitoring/xymon/pull/413) | a `sysusers.d` snippet | draft |
| [#414](https://github.com/xymon-monitoring/xymon/pull/414) | `INSTALLSTATICWWWDIR` (build placement) + `XYMONSTATICWWWDIR` (runtime — re-bases the `help` dir off `XYMONNOTESDIR` onto the static tree in `lib/links.c`) | draft |
| [#415](https://github.com/xymon-monitoring/xymon/pull/415) | `devel`'s systemd unit generated from the build's paths, plus its preset, tmpfiles and defaults files and `INSTALLSYSTEMDDIR` | draft |
| [#443](https://github.com/xymon-monitoring/xymon/pull/443) | `XYMONCACHEWWWDIR` — lets `rep`/`snap` move to `/var/cache` (not consumed here yet) | draft |

Each is opt-in behind a variable or an unused target, so it is a no-op for
an existing build, which is why
#409, #410 and #411 merge in any order.
[#421](https://github.com/xymon-monitoring/xymon/pull/421) is separate: it
fixes flaky upstream server tests that drew xymond's port from the
ephemeral range, and changes no shipped code.

The spec adopts each feature as it lands, via its own consuming PRs — e.g.
[xymon-rpm #4](https://github.com/xymon-monitoring/xymon-rpm/pull/4) swaps the
hand-rolled static `mv`+`ln` loop for `INSTALLSTATICWWWDIR` once #414 merges.

`rpm/terabithia/` archives the reference spec and README from
<https://repo.terabithia.org/rpms/xymon/> for provenance only; it is
never built.

## Drift detection

Two nightly schedules catch upstream moving underneath this packaging:

- **`build.yml`** rebuilds `main` (cron `17 3 * * *`). If an upstream
  change moves an install path or a configure flag, the build goes red
  the next day rather than at the next release.
- **`docs-drift.yml`** runs `tests/docs.sh` (cron `47 3 * * *`, plus
  `workflow_dispatch` and pushes touching the doc or checker). It parses
  the origin and state columns above out of this file and tests them
  against `main` and `devel` — so a merged PR or a file newly landed on
  `devel` reports here rather than leaving a stale sentence. It is a
  separate workflow on purpose: a stale doc is worth a red run, not a
  held release, so it must not gate publishing.

## Where the packaging should eventually live

Packaging lives here so it can iterate without a review round per change.
Once the spec is stable, the intent is to move it and the build workflow
into `xymon-monitoring/xymon` — the convention Debian packaging follows —
leaving this repository as the publishing target. Upstream already
carries two unmaintained packagings of its own: `rpm/xymon.spec` (last
touched 2014, still installing SysV init scripts) and `debian/` (2019);
deciding what happens to those is part of any move.
