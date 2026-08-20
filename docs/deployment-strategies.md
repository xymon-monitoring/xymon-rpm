# Deployment strategies: how Xymon packagings split server and client

Every Xymon packaging faces the same fact and answers it differently.
The fact: upstream's `./configure --server` build **always** produces
the server *with its client* — the server monitors itself through that
client tree, so it is a component of the server, not an optional
extra (`build/Makefile.rules` sets `XYMONCLIENTHOME = $(XYMONTOPDIR)/client`
for the server build and installs it via the same `install-client`
target the client variant uses). Only the separate `./configure
--client` variant produces a client *alone* — and that build differs
just by `-DCLIENTONLY`, which strips server-only code out of the
library to make binaries smaller; it adds nothing the server build's
client lacks.

Meanwhile a fleet needs the opposite emphasis: hundreds of client-only
hosts that must install something small, and one server. So every
packaging must decide what a "client package" is and how it relates to
the server package. Four answers exist in the wild; all four were
verified against their primary sources (Debian's `debian/rules`,
`control`, and the shipped `.deb` contents; Terabithia's `xymon.spec`;
FreeBSD's port Makefiles and `pkg-plist`).

## Debian: amputate, then re-attach with a dependency

One `--server` build. The client tree the build produced is cut out of
the `xymon` package (the shipped `.deb` contains no
`/usr/lib/xymon/client` at all) and moved into `xymon-client`; then
`xymon` declares `Depends: xymon-client` to pull it back at install
time. Every server host therefore installs both packages, and the
filesystem ends up exactly as the build made it — only the package
ownership says otherwise.

The cost surfaces at runtime: because two packages exist, two units
exist (`xymon.service`, `xymon-client.service`), and a guard must keep
the client unit from double-reporting on a server. Debian's guard is
`ExecCondition=test ! -x /usr/lib/xymon/server/bin/xymond` — on a
server the client unit starts as a clean no-op. One-directional and
gentle, but the underlying inversion also forces oddities like the
analysis daemon `xymond_client` shipping *twice* (once per package, at
different paths) in the packaging whose split exists to avoid shipping
files twice.

## Terabithia: self-contained server, standalone client

Two builds: `configure.client && make client` first (the result set
aside), then a full server build. The server package embeds its own
client and declares **no dependency** on `xymon-client`; its
description says plainly that the client package "does not need to be
installed on a system that is already running as a Xymon server
(indeed, it conflicts with it)". The exclusion is *implicit* — both
packages ship `/usr/bin/xymon`, `/usr/sbin/xymonlaunch` and friends
from different builds, so rpm refuses coinstallation with raw
file-conflict errors. Both packages ship the **same single unit name**,
`xymonlaunch.service`, so no runtime guard is ever needed.

The architecture is right; the implementation shows its age: the second
build is redundant (it only makes smaller binaries), the exclusion has
no clean metadata, and the scriptlets carry literal "this is a hack"
comments for states the design should have made unrepresentable.

## FreeBSD: two ports, no relationship at all

Two independent ports, two builds. `net-mgmt/xymon-client` is a true
`CLIENTONLY=yes` build. `net-mgmt/xymon-server` runs the full server
build and then **discards** the client tree it produced — the pkg-plist
ships no `client/` files. No dependency, no conflict: the ports are
co-installable, each with its own rc script, and nothing stops both
from running or a server from running with no client at all.
Coordination is entirely the administrator's job. The most honest about
being two separate products; the least protective.

## This packaging: self-contained server, one build, explicit conflict

The strategy here takes Terabithia's architecture at Debian's build
cost, with the sharp edges filed off:

- **One `--server` build.** Its client tree is complete (verified:
  same `install-client` target, same programs; `-DCLIENTONLY` only
  removes code), so both packages ship from it and their shared files
  are byte-identical.
- **`xymon` is the whole build output** — server plus embedded client.
  It needs nothing.
- **`xymon-client` is the same client tree packaged alone** for hosts
  that are not the server.
- **`Conflicts: xymon-client`** states the exclusion in metadata: `dnf
  install xymon` on a client host fails with a clear message instead
  of Debian's silent layering or Terabithia's file-collision noise.
- **One unit name everywhere.** Both packages ship the same
  `xymonlaunch.service`; its `ExecStart`, `xymonlaunch-run`, picks the
  server tree when installed and otherwise runs the client in the
  foreground. What genuinely differs between the roles rides in a
  per-role drop-in under `xymonlaunch.service.d/` (server: protect
  xymond's children on stop; client: wait for the network at boot),
  each shipped only by its role's package. `systemctl status
  xymonlaunch` means the same thing on every host, and the
  double-reporting hazard is unrepresentable — no
  `Conflicts=`/`ExecCondition` guard exists because nothing needs
  guarding.
- **Role changes are one transaction**, and the scriptlets are
  swap-aware: each package skips disabling the shared unit when the
  other role's packaged drop-in is already on disk (installs precede
  erases), so enablement survives the swap. The old role's process is
  deliberately left running until the `systemctl restart` — see the
  README's install section for the runnable recipe.

The irreducible costs, accepted deliberately: the client tree exists in
two packages *in the repository* (never twice on a host — they
conflict), and a role change is an explicit `dnf swap` rather than
automatic (`Obsoletes:` would convert every client-only host into a
server on its next routine update; there is no safe automatic answer
in rpm).

## Side by side

| | Debian | Terabithia | FreeBSD | here |
| --- | --- | --- | --- | --- |
| Builds | 1 | 2 | 2 | 1 |
| Server package is self-contained | no | yes | no — discards its client | yes |
| Server ↔ client relation | Depends | none (implicit conflict) | none at all | none (explicit `Conflicts:`) |
| Install server on a client host | layers on top | fails, ugly errors | coexists silently | fails, clear message |
| Units | 2 + `ExecCondition` guard | 1 | 2 rc scripts, unguarded | 1, no guard |
| Double-reporting possible | guarded against | unrepresentable | yes | unrepresentable |
| Role change | maintainer scripts | scriptlet hacks | manual | `dnf swap`, defined |

## Migrating from the old layout of this packaging

Before this design, `xymon` required `xymon-client` (the Debian shape)
and a separate `xymon-client.service` carried a `Conflicts=` guard.
Upgrading:

- **Client-only hosts** upgrade normally; the client package's `%post`
  moves an enabled/running `xymon-client.service` over to
  `xymonlaunch.service`.
- **Server hosts** have both packages installed, which the new `xymon`
  conflicts with; the upgrade is one explicit
  `dnf swap xymon-client xymon`. Until that is run, the conflict makes
  the host's whole `dnf upgrade` transaction unsolvable — unrelated
  packages included — so an unattended updater on such a host stops
  applying updates entirely, silently. Acceptable only because this
  packaging is experimental and has no production users; a stable
  release would need a `%triggerun`-based migration or a transitional
  package instead.
