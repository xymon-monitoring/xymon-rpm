# Upstream: what this packaging adds, and what it is sending back

`xymon-monitoring/xymon` and this repository are separate on purpose:
packaging iterates faster than a source tree can review it. This file
records what had to be written here because upstream has no equivalent,
and which of those gaps are being closed upstream so the spec can delete
its workaround.

## Where the files in `rpm/sources/` come from

Upstream `main` ships no systemd or SELinux integration at all, and the
only logrotate file it has is inside the unmaintained `rpm/` packaging
described at the end of this page. It is not that nobody wrote any: the
`devel` (4.4) branch has `tools/xymonlaunch.service`, its preset and
`xymon-tmpfiles.conf`, written by J.C. Cleaver, and they have simply
never been merged to `main`. So the files below are adapted from there where one existed and
written here where none did. Nothing in this repository waits on an
upstream merge to work.

That unmerged unit already wraps `xymoncmd` around `xymonlaunch
--no-daemon`, with the comment *"we wrap in xymoncmd to eliminate the
need for the bulk of the old init script"* — the same conclusion this
packaging reached independently, by testing, after withdrawing a PR that
would have added a `foreground` mode to `runclient.sh`. The answer had
been on `devel` since 2016.
[#415](https://github.com/xymon-monitoring/xymon/pull/415) carries it to
`main`, with the paths substituted from the build rather than hardcoded
to `/usr/bin` and `/usr/sbin`, so it serves a source install and any
packaging rather than only an RPM one.

| File | Origin | Why |
| --- | --- | --- |
| `xymonlaunch.service` | adapted from `devel` | eleven directives are verbatim from `devel`'s `tools/xymonlaunch.service`, including the `xymoncmd` wrapping. Four things differ, all of them this packaging's: `ExecStart` calls `xymonlaunch-run` for the role dispatch, the kill semantics move into the server's drop-in rather than applying to both roles, `Alias=xymon-client.service` is dropped because one unit already serves both roles, and the second `EnvironmentFile` is `/etc/sysconfig/xymon-client` rather than `/etc/default/xymonlaunch`. [#415](https://github.com/xymon-monitoring/xymon/pull/415) brings the `devel` unit to `main` with substituted paths; landing it would leave only those four differences here |
| `xymonlaunch-run`, `xymonlaunch-server.conf`, `xymonlaunch-client.conf` | written here | the role dispatch itself. `xymonlaunch-run` picks the tree by which role's drop-in is present and runs `xymoncmd xymonlaunch --no-daemon` for either; the drop-ins carry what differs between roles. All three exist because these two packages conflict and share one unit, which no other packaging does |
| `xymonlaunch.service.preset` | byte-identical to `devel`'s | the file is one line and the same one. What is ours is shipping it *only* in the server package: a fresh client must not enable itself against the baked-in `XYMSRV` |
| `xymon.sysusers` | written here | [xymon#413](https://github.com/xymon-monitoring/xymon/pull/413) proposes it upstream |
| `xymon-tmpfiles.conf` | byte-identical to `devel`'s | creates `/run/xymon`, which nothing uses yet (see the README's known gaps) |
| `xymon-sysctl.conf` | byte-identical to `devel`'s | the backfeed-queue tunables; `main` has no equivalent |
| `xymon.logrotate` | adapted from `devel` | the `devel` copy's postrotate HUPs `xymonlaunch`, which `main` does not relay ([xymon#172](https://github.com/xymon-monitoring/xymon/pull/172)); `copytruncate` until it does |
| `xymon-client.default`, `xymonlaunch.default` | adapted from `devel` | both name this packaging's own config paths instead of upstream's; `xymon-client.default` also documents `XYMONSERVERS`, which only patched clients read |
| `xymon.te`, `xymon-client.te`, `bb.xml` | copied from `devel` | reference material, shipped as `%doc` only — the policy modules are not compiled by default (see the README's known gaps) |

The upstream gaps these work around are proposed as small PRs rather
than waited on — each lands a feature that lets this spec delete a
workaround:

| PR | What it adds | |
| --- | --- | --- |
| [#410](https://github.com/xymon-monitoring/xymon/pull/410) | `make install-devel` installs the libraries and headers | open |
| [#411](https://github.com/xymon-monitoring/xymon/pull/411) | `INSTALLCLIENT*DIR` | open |
| [#414](https://github.com/xymon-monitoring/xymon/pull/414) | `INSTALLSTATICWWWDIR` | open |
| [#415](https://github.com/xymon-monitoring/xymon/pull/415) | `devel`'s systemd unit, generated from the build's paths, plus `INSTALLSYSTEMDDIR` | open |
| [#416](https://github.com/xymon-monitoring/xymon/pull/416) | an unknown verb exits non-zero, not 0 | open |
| [#409](https://github.com/xymon-monitoring/xymon/pull/409) | installs the `lib/` diagnostics | draft |
| [#412](https://github.com/xymon-monitoring/xymon/pull/412) | `INSTALLHTTPDCONFDIR` | draft |
| [#413](https://github.com/xymon-monitoring/xymon/pull/413) | a `sysusers.d` snippet | draft |

The five open ones merge in any order — all 120 checked — and every one
is a no-op for an existing build: each is opt-in behind a variable or a
target nobody has to invoke. #413 and #415 are systemd-specific; the
rest are plain make and POSIX shell, verified on Debian as well as EL.

Two of the open ones delete something Debian carries by hand as well —
`debian/rules` does #411's symlinks at lines 96-98 and #414's at 62-65 —
and #415 gives every systemd distribution a unit instead of each writing
its own. #416 is the odd one out, a bug fix this spec does not need:
both `runclient.sh` and `xymon.sh` end their case statement with
`break`, which does nothing outside a loop, so a mistyped verb prints
usage and exits **0**.

The drafts are parked, not abandoned: each replaces a workaround costing
one `mv` or three lines of `%install`, not enough to spend upstream
review on. #408 was withdrawn outright — `xymoncmd` already runs the
client in the foreground, so nothing was needed.

A lesson worth keeping: #415 appends to `INSTALLTARGETS` rather than
editing the three assignments that set it, because those are the lines
every install change touches. Editing them directly conflicted with #410
in every ordering.

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
