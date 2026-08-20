# Deployment strategies: how Xymon packagings split server and client

Upstream's `./configure --server` build **always** produces the server
*with* its client: `build/Makefile.rules` sets `XYMONCLIENTHOME =
$(XYMONTOPDIR)/client` and installs it through the same
`install-client` target the client-only build uses. The server monitors
itself through that tree, so it is a component of the server, not an
extra. The separate `--client` build differs only by `-DCLIENTONLY`,
which strips server-only code to make binaries smaller — it adds
nothing the server build's client lacks.

A fleet needs the opposite emphasis: one server, and many client-only
hosts that should install something small. So each packaging must
decide what a "client package" is and how it relates to the server
package. Four answers exist, all verified here against their primary
sources — Debian's `debian/rules`, `control` and shipped `.deb`;
Terabithia's `xymon.spec`; FreeBSD's port Makefiles and `pkg-plist`.

## Debian: amputate, then re-attach with a dependency

One `--server` build. The client tree it produced is cut out of the
`xymon` package — the shipped `.deb` contains no `/usr/lib/xymon/client`
at all — moved into `xymon-client`, and pulled back at install time by
`Depends: xymon-client`. Every server installs both packages, so the
filesystem ends up as the build made it; only package ownership says
otherwise.

The cost is at runtime. Two packages mean two units (`xymon.service`,
`xymon-client.service`), so a guard must stop the client unit
double-reporting on a server:
`ExecCondition=test ! -x /usr/lib/xymon/server/bin/xymond`, which makes
it a clean no-op there. Gentle, but the same inversion has the analysis
daemon `xymond_client` shipping *twice*, once per package at different
paths — in the packaging whose split exists to avoid duplicate files.

## Terabithia: self-contained server, standalone client

Two builds: `configure.client && make client`, the result set aside,
then a full server build. The server package embeds its own client and
declares **no dependency** on `xymon-client`; its description says the
client package "does not need to be installed on a system that is
already running as a Xymon server (indeed, it conflicts with it)". That
conflict is *implicit*: both packages ship `/usr/bin/xymon`,
`/usr/sbin/xymonlaunch` and friends from different builds, so rpm
refuses coinstallation with raw file-conflict errors. Both ship the
**same unit name**, `xymonlaunch.service`, so no runtime guard is ever
needed.

The architecture is right; the implementation shows its age. The second
build is redundant, the exclusion has no clean metadata, and the
scriptlets carry literal "this is a hack" comments for states the
design should have made unrepresentable.

## FreeBSD: two ports, no relationship at all

Two independent ports, two builds. `net-mgmt/xymon-client` is a true
`CLIENTONLY=yes` build. `net-mgmt/xymon-server` runs the full server
build, but its `pkg-plist` ships no `client/` files, so the packaged
server contains none. Neither port depends on or conflicts with the
other: they install to different paths, are co-installable, and each
has its own rc script. Nothing prevents both from running, or a server
from running with no client at all — coordination is the
administrator's job. The most honest about being two products, the
least protective.

## This packaging: self-contained server, one build, explicit conflict

Terabithia's architecture at Debian's build cost, with the sharp edges
filed off:

- **One `--server` build**, whose client tree is complete, so both
  packages ship from it and their shared files are byte-identical.
- **`xymon` is the whole build output**, server plus embedded client,
  and needs nothing. **`xymon-client` is that same client tree packaged
  alone** for hosts that are not the server.
- **`Conflicts: xymon-client`** puts the exclusion in metadata: `dnf
  install xymon` on a client host fails with a clear message, rather
  than Debian's silent layering or Terabithia's file-collision noise.
- **One unit name everywhere.** Both packages ship the same
  `xymonlaunch.service`, whose `ExecStart` (`xymonlaunch-run`) selects
  the server tree when installed and otherwise runs the client in the
  foreground. What differs between roles rides in a drop-in under
  `xymonlaunch.service.d/`, shipped only by that role's package: the
  server protects xymond's children on stop, the client waits for the
  network at boot. The double-reporting hazard is unrepresentable, so
  no guard exists to need maintaining.
- **Role changes are one transaction.** The scriptlets detect a swap by
  the other role's drop-in already being on disk (installs precede
  erases). The departing package stops the service *while its own
  drop-in still applies* — that is what lets a server's xymond finish
  its checkpoints — and leaves enablement alone, so the host still
  starts at boot. `systemctl restart` then brings the new role up. The
  README's install section has the runnable recipe.

Two costs, accepted deliberately: the client tree exists in two
packages *in the repository* (never twice on a host — they conflict),
and a role change is an explicit `dnf swap` rather than automatic.
`Obsoletes:` would be the automatic route, and it would convert every
client-only host into a server at its next routine update.

## Side by side

| | Debian | Terabithia | FreeBSD | here |
| --- | --- | --- | --- | --- |
| Builds | 1 | 2 | 2 | 1 |
| Server package self-contained | no | yes | no — ships no client | yes |
| Server ↔ client relation | Depends | none (implicit conflict) | none at all | none (explicit `Conflicts:`) |
| Install server on a client host | layers on top | fails, ugly errors | coexists silently | fails, clear message |
| Units | 2 + `ExecCondition` guard | 1 | 2 rc scripts, unguarded | 1, no guard |
| Double-reporting possible | guarded against | unrepresentable | yes | unrepresentable |
| Role change | maintainer scripts | scriptlet hacks | manual | `dnf swap`, defined |

## Where the files land

The same four packagings disagree just as much about *paths*. Upstream
installs everything under one root — `XYMONTOPDIR`, with `server/` and
`client/` beside each other — and then leaves each packager to decide
how much of that to bend towards the FHS. All of the below was read out
of the shipped packages and ports, not from documentation.

| | here | Debian | Terabithia | FreeBSD |
| --- | --- | --- | --- | --- |
| Server config | `/etc/xymon/` | `/etc/xymon/` | `/etc/xymon/` | `…/www/xymon/server/etc/` |
| Client config | `/usr/lib/xymon/client/etc/` | `/etc/xymon/` | `/etc/xymon-client/` | `…/www/xymon/client/etc/` |
| Server binaries | `/usr/lib/xymon/server/bin/` | `/usr/lib/xymon/server/bin/` | `/usr/libexec/xymon/`, `/usr/sbin/xymond` | `…/www/xymon/server/bin/` |
| Client binaries | `/usr/lib/xymon/client/bin/` | `/usr/lib/xymon/client/bin/` | `/usr/libexec/xymon-client/` | `…/www/xymon/client/bin/` |
| Web assets | `/var/lib/xymon/www/` | `/usr/share/xymon/` | `/var/www/xymon/` | `…/www/xymon/server/www/` |
| Server data | `/var/lib/xymon/` | `/var/lib/xymon/` | `/var/lib/xymon/` | `…/www/xymon/data/` |
| Logs | `/var/log/xymon/` | `/var/log/xymon/` | `/var/log/xymon/` | `/var/log/xymon/` |

(FreeBSD's `…` is `${PREFIX}/www`, normally `/usr/local/www` — it keeps
upstream's single tree almost untouched and simply puts it under the
web root.)

Three degrees of intervention:

- **Terabithia rewrites the layout.** Binaries move to
  `/usr/libexec/<pkg>/`, the two roles get separate config directories,
  web content goes to `/var/www/`, and the daemons an admin invokes are
  linked into `/usr/sbin/`. That is why its spec carries hundreds of
  `sed` rules rewriting `@XYMONTOPDIR@/server/bin` and friends, and a
  large patch set to match.
- **Debian moves configuration and web content only.** It keeps
  upstream's `/usr/lib/xymon/{server,client}` binary tree but pulls all
  configuration — both roles' — into `/etc/xymon`, and the static web
  assets into `/usr/share/xymon`.
- **Here, upstream's own symlinks do the work.** The tree stays exactly
  as the `--server` build lays it out, and the build's own links
  redirect everything that must not live in `/usr/lib`: `server/etc →
  /etc/xymon`, `server/www → /var/lib/xymon/www`, `server/tmp →
  /var/lib/xymon/tmp`, `client/logs → /var/log/xymon`, `client/tmp →
  /var/tmp`. So the layout matches upstream's documentation while
  nothing writes inside `/usr/lib`, and the spec needs no path
  rewriting and no patches.

**One place this packaging is the outlier.** The client's editable
configuration — `xymonclient.cfg` (which holds `XYMSRV`),
`clientlaunch.cfg`, `localclient.cfg` — is a real directory at
`/usr/lib/xymon/client/etc/`, because upstream provides no symlink for
the client the way it does for the server. Debian and Terabithia both
place client configuration under `/etc`, and the FHS wants `/usr`
shareable and read-only. It works — the files are `%config(noreplace)`,
so upgrades keep local edits, and `tests/packages.sh` asserts that for
both roles — but the file an admin edits most often on a client host is
in the least expected place. Closing the gap would mean shipping those
configs in `/etc/xymon-client/` and making `client/etc` a symlink to
it, which is a layout change with a migration cost for anyone already
on the snapshot channel.

## Migrating from the old layout of this packaging

Before this design, `xymon` required `xymon-client` and a separate
`xymon-client.service` carried a `Conflicts=` guard.

- **Client-only hosts** upgrade normally: the client package's `%post`
  carries enablement and any running instance over to
  `xymonlaunch.service`.
- **Server hosts** have both packages installed, which the new `xymon`
  conflicts with, so the upgrade is one explicit `dnf swap xymon-client
  xymon`. Until that runs, the conflict makes the host's whole `dnf
  upgrade` unsolvable — unrelated packages included — so an unattended
  updater silently stops applying updates. Acceptable only because this
  packaging is experimental and has no production users; a stable
  release would need a `%triggerun` migration or a transitional package.
