# Upstream: what this packaging adds, and what it is sending back

`xymon-monitoring/xymon` and this repository are separate on purpose:
packaging iterates faster than a source tree can review it. This file
records what had to be written here because upstream has no equivalent,
and which of those gaps are being closed upstream so the spec can delete
its workaround.

## Where the files in `rpm/sources/` come from

Upstream `main` ships no systemd, logrotate or SELinux integration at
all. It is not that nobody wrote any: the `devel` (4.4) branch has
`tools/xymonlaunch.service`, its preset and `xymon-tmpfiles.conf`,
written by J.C. Cleaver, and they have simply never been merged to
`main`. So the files below are adapted from there where one existed and
written here where none did. Nothing in this repository waits on an
upstream merge to work.

The unmerged unit is worth reading before changing ours: it already
wraps `xymoncmd` around `xymonlaunch --no-daemon`, with the comment
*"we wrap in xymoncmd to eliminate the need for the bulk of the old init
script"*. That is the same conclusion this packaging reached
independently, by testing, after withdrawing an upstream PR that would
have added a `foreground` mode to `runclient.sh` — the answer had been
sitting on `devel` since 2015.

| File | Origin | Why |
| --- | --- | --- |
| `xymonlaunch.service` | adapted from `devel` | eleven directives are verbatim from `devel`'s `tools/xymonlaunch.service`, including the `xymoncmd` wrapping. What differs is this packaging's: `ExecStart` calls `xymonlaunch-run` for the role dispatch, and the kill semantics move into the server's drop-in rather than applying to both roles |
| `xymonlaunch-run`, `xymonlaunch-server.conf`, `xymonlaunch-client.conf` | written here | the role dispatch itself. `xymonlaunch-run` picks the tree by which role's drop-in is present and runs `xymoncmd xymonlaunch --no-daemon` for either; the drop-ins carry what differs between roles. All three exist because these two packages conflict and share one unit, which no other packaging does |
| `xymonlaunch.service.preset` | byte-identical to `devel`'s | the file is one line and the same one. What is ours is shipping it *only* in the server package: a fresh client must not enable itself against the baked-in `XYMSRV` |
| `xymon.sysusers` | written here | [xymon#413](https://github.com/xymon-monitoring/xymon/pull/413) proposes it upstream |
| `xymon-tmpfiles.conf` | written here | creates `/run/xymon`, which nothing uses yet (see the README's known gaps) |
| `xymon-sysctl.conf` | adapted from `devel` | the backfeed-queue tunables; `main` has no equivalent |
| `xymon.logrotate` | adapted from `devel` | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay ([xymon#172](https://github.com/xymon-monitoring/xymon/pull/172)); `copytruncate` until it does |
| `xymon-client.default`, `xymonlaunch.default` | adapted from `devel` | they document `XYMONSERVERS`, which only patched clients read, and name this packaging's own config paths |
| `xymon.te`, `xymon-client.te`, `bb.xml` | copied from `devel` | reference material, shipped as `%doc` only — the policy modules are not compiled by default (see the README's known gaps) |

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

They merge in any order — checked across all 5040 orderings. All but
#410 are no-ops until their variable is set; #410 adds `install-libs` to
the server's default `INSTALLTARGETS`, so a plain `make install` gains
the libraries and headers. That is raised on the PR, since #409 gates
the same kind of addition and the two should agree. Only #413 is
systemd-specific; the rest are plain make and POSIX shell, verified on
Debian as well as EL.

The drafts are parked, not abandoned: each replaces a workaround costing
one `mv` or three lines of `%install`, which is not enough to spend
upstream review on. The open three each delete something Debian carries
by hand too — `debian/rules` does #411's symlinks at lines 96-98 and
#414's at 72-74. A seventh, #408, was withdrawn: `xymoncmd` already runs
the client in the foreground, so nothing was needed.

`rpm/terabithia/` archives the reference spec and README from
<https://repo.terabithia.org/rpms/xymon/> — a single unmirrored host —
for provenance only; it is never built.

## Where the packaging should eventually live

Packaging lives here so it can iterate without a review round per
change. Once the spec is stable, the intent is to move it and the build
workflow into `xymon-monitoring/xymon` — the convention Debian packaging
follows — leaving this repository as the publishing target. The nightly
build doubles as a drift detector: an upstream change that moves an
install path or a configure flag goes red here the next day.

Note that upstream already carries two packagings of its own, both
unmaintained: `rpm/xymon.spec`, last touched in 2014 and still
installing SysV `/etc/init.d` scripts, and `debian/`, last touched in
2019. Deciding what happens to those is part of any move.
