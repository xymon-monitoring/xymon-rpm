# Upstream: what this packaging adds, and what it sends back

The spec builds the `xymon-monitoring/xymon` tree **with no patches at
all; fixes belong upstream.** This repository and that one are separate
on purpose: packaging iterates faster than a source tree can review it.
This file records what had to be written here because upstream has no
equivalent, and points to the issue that tracks which of those gaps are
being closed upstream so the spec can delete its workaround.

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
by testing. [xymon#415](https://github.com/xymon-monitoring/xymon/pull/415)
carries it to `main` with paths substituted from the build rather than
hardcoded, so it serves a source install and any packaging, not only RPM.

| File | Origin | Why | Upstream PR |
| --- | --- | --- | --- |
| `xymonlaunch.service` | adapted from `devel` | eleven directives are verbatim from `devel`'s `tools/xymonlaunch.service`, including the `xymoncmd` wrapping. Four things differ, all this packaging's: `ExecStart` calls `xymonlaunch-run` for role dispatch, the kill semantics move into the server's drop-in, `Alias=xymon-client.service` is dropped because one unit serves both roles, and the second `EnvironmentFile` is `/etc/sysconfig/xymon-client`. Once it lands, only those four differences remain | [xymon#415](https://github.com/xymon-monitoring/xymon/pull/415) |
| `xymonlaunch-run`, `xymonlaunch-server.conf`, `xymonlaunch-client.conf` | written here | the role dispatch itself. `xymonlaunch-run` picks the tree by which role's drop-in is present and runs `xymoncmd xymonlaunch --no-daemon`; the drop-ins carry what differs. All three exist because these two packages conflict and share one unit | — packaging-only |
| `xymonlaunch.service.preset` | byte-identical to `devel`'s | one line, the same one. What is ours is shipping it *only* in the server package: a fresh client must not enable itself against the baked-in `XYMSRV` | [xymon#415](https://github.com/xymon-monitoring/xymon/pull/415) |
| `clientupdate` | written here | stands in for upstream's `clientupdate` in both packages: a packaged client is updated by the package manager, not by a tarball its server pushes. Deleting upstream's instead, as Terabithia does (TBT 8), needs `xymonclient.sh` patched too, or every client run logs the missing program; the script's header has the detail | — packaging-only |
| `xymon.sysusers` | written here | declares the `xymon` system user and group. Which account a package creates is packaging policy; [xymon#413](https://github.com/xymon-monitoring/xymon/pull/413) proposed it upstream and was closed on that ground | — packaging-only |
| `xymon-tmpfiles.conf` | byte-identical to `devel`'s | creates `/run/xymon`, which nothing uses yet — until [xymon#219](https://github.com/xymon-monitoring/xymon/pull/219) points pidfiles and `rrd` control sockets there via `XYMONRUNDIR` (see the README's known gaps) | [xymon#415](https://github.com/xymon-monitoring/xymon/pull/415) |
| `xymon-sysctl.conf` | byte-identical to `devel`'s | the backfeed-queue tunables; `main` has no equivalent | — none |
| `xymon.logrotate` | adapted from `devel` | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay yet; `copytruncate` until it does | [xymon#172](https://github.com/xymon-monitoring/xymon/pull/172) (the `SENDHUP` enabler) |
| `xymon-client.default`, `xymonlaunch.default` | adapted from `devel` | both name this packaging's config paths instead of upstream's; `xymon-client.default` also documents `XYMONSERVERS`, which only patched clients read | [xymon#415](https://github.com/xymon-monitoring/xymon/pull/415) (`xymonlaunch.default` only) |
| `xymon.te` | adapted from `devel` | the server's policy module, built and loaded by default; adds `xymon_port_t`, the type `%posttrans` gives port 1984 so the CGIs may reach xymond (see [docs/selinux.md](selinux.md)) | — packaging-only |
| `xymon-client.te` | copied from `devel` | the client's policy module, built and loaded by default | — packaging-only |

## Gaps sent back upstream

The upstream pull requests this packaging waits on, and the state of each,
are tracked in one issue,
[xymon-rpm#109](https://github.com/xymon-monitoring/xymon-rpm/issues/109),
not here: their state changes every time one moves, and a document only
changes when someone edits it. That issue is the only copy. It has the
build and install compensations and the runtime shortfalls, each row naming
the pull request and what it would add; README *Known gaps* says what each
shortfall means on a host. A row goes once its pull request merges.

`tests/docs.sh` and `tests/compensations.sh` read the issue's body, and find
it through the link above, so that link is the one place its number is
written.

The spec adopts each feature as it lands, via its own consuming PRs — e.g.
[xymon-rpm #4](https://github.com/xymon-monitoring/xymon-rpm/pull/4) swaps the
hand-rolled static `mv`+`ln` loop for `INSTALLSTATICWWWDIR` once xymon#414
merges.

`rpm/terabithia/` archives the reference spec and the documentation published
beside it at <https://repo.terabithia.org/rpms/xymon/>, for provenance only;
it is never built. The source RPM they describe, `xymon-4.3.30-1.el8.src.rpm`,
is too large for the tree and is attached to the
[`terabithia-4.3.30-1-reference`](https://github.com/xymon-monitoring/xymon-rpm/releases/tag/terabithia-4.3.30-1-reference)
release instead.

## Drift detection

Two nightly schedules catch upstream moving underneath this packaging:

- **`build.yml`** rebuilds `main` (cron `17 0 * * *`). If an upstream
  change moves an install path or a configure flag, the build goes red
  the next day rather than at the next release.
- **`docs-drift.yml`** runs `tests/docs.sh` (cron `47 0 * * *`, plus
  `workflow_dispatch` and pushes touching the doc or checker). It parses
  the origin column above out of this file and tests it against `devel`,
  and the state column out of the tracking issue and tests it against the
  pull requests — so a merged PR or a file newly landed on `devel` reports
  here rather than leaving a stale sentence or a stale row. It is a
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
