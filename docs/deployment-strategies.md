# Deployment strategies: how Xymon packagings split server and client

Upstream's `./configure --server` build **always** produces the server
*with* its client: `build/Makefile.rules` sets `XYMONCLIENTHOME =
$(XYMONTOPDIR)/client` and installs it through the same `install-client`
target the client-only build uses. The server monitors itself through
that tree, so it is a component of the server, not an extra. The
separate `--client` build differs only by `-DCLIENTONLY`, which strips
server-only code to make binaries smaller; it adds nothing the server
build's client lacks.

A fleet needs the opposite emphasis: one server, many client-only hosts
that should install something small. So each packaging must decide what
a "client package" is and how it relates to the server package. Four
answers exist, all verified below against their primary sources —
Debian's `debian/rules`, `control` and shipped `.deb`; Terabithia's
`xymon.spec`; FreeBSD's port Makefiles and `pkg-plist`.

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
it a clean no-op there. The split also inverts which package owns what:
`xymon.service` runs the *client* package's `xymonlaunch`, and the
analysis daemon `xymond_client` was moved into `xymon-client` (Debian
#903614) with a symlink left behind in the server tree. Nothing is
duplicated, but nothing in the server package stands alone either.

## Terabithia: self-contained server, standalone client

Two builds: `configure.client && make client`, the result set aside,
then a full server build. The server package embeds its own client and
declares **no dependency** on `xymon-client`; its description says that
package "does not need to be installed on a system that is already
running as a Xymon server (indeed, it conflicts with it)". That conflict
is *implicit*: both ship `/usr/bin/xymon`, `/usr/sbin/xymonlaunch` and
friends from different builds, so rpm refuses coinstallation with raw
file-conflict errors. Both ship the **same unit name**, so no runtime
guard is needed.

The architecture is right; the implementation shows its age. The second
build is redundant, the exclusion has no clean metadata, and the
scriptlets carry literal "this is a hack" comments for states the design
should have made unrepresentable.

## FreeBSD: two ports, no relationship at all

Two independent ports, two builds. `net-mgmt/xymon-client` is a true
`CLIENTONLY=yes` build. `net-mgmt/xymon-server` runs a server build with
the client cut out of it: the port edits `build/Makefile.rules` to drop
`client` from the build targets and `install-client` from the install
targets, so the packaged server never contains one — the only packaging
that removes it at the source rather than after the fact. Neither port
depends on or conflicts with the
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
  `xymonlaunch.service`, whose `ExecStart` (`xymonlaunch-run`) picks the
  tree by which role's drop-in is present and runs `xymoncmd xymonlaunch
  --no-daemon` for either — upstream's own `runclient.sh` and `xymon.sh`
  both fork and exit, leaving `Type=simple` nothing to supervise. What
  differs between roles rides in a drop-in shipped only by that role's
  package: the server protects xymond's children on stop, the client
  waits for the network at boot. Double-reporting is unrepresentable, so
  no guard exists to maintain.
- **Role changes are one transaction.** The scriptlets detect a swap by
  the other role's drop-in already being on disk (installs precede
  erases). The departing package stops the service *while its own
  drop-in still applies* — that is what lets a server's xymond finish
  its checkpoints — and leaves enablement alone, so the host still
  starts at boot. `systemctl restart` brings the new role up.

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
| Client config | `/etc/xymon-client/` | `/etc/xymon/` | `/etc/xymon-client/` | `…/www/xymon/client/etc/` |
| Server binaries | `/usr/lib/xymon/server/bin/` | `/usr/lib/xymon/server/bin/` | `/usr/libexec/xymon/`, `/usr/sbin/xymond` | `…/www/xymon/server/bin/` |
| Client binaries | `/usr/lib/xymon/client/bin/` | `/usr/lib/xymon/client/bin/` | `/usr/libexec/xymon-client/` | `…/www/xymon/client/bin/` |
| Web assets (static) | `/usr/share/xymon/` | `/usr/share/xymon/` | `/var/www/xymon/` | `…/www/xymon/server/www/` |
| Web pages (generated) | `/var/lib/xymon/www/` | `/var/lib/xymon/www/` | `/var/www/xymon/` | `…/www/xymon/server/www/` |
| Server data | `/var/lib/xymon/` | `/var/lib/xymon/` | `/var/lib/xymon/` | `…/www/xymon/data/` |
| Logs | `/var/log/xymon/` | `/var/log/xymon/` | `/var/log/xymon/` | `…/www/xymon/data/logs/` |

(FreeBSD's `…` is `${PREFIX}/www`, normally `/usr/local/www` — it keeps
upstream's single tree almost untouched and simply puts it under the
web root.)

Three degrees of intervention:

- **Terabithia rewrites the layout.** Binaries move to
  `/usr/libexec/<pkg>/`, the two roles get separate config directories,
  web content goes to `/var/www/`, and the daemons an admin invokes are
  linked into `/usr/sbin/`. That is why its spec rewrites
  `@XYMONTOPDIR@/server/bin` and friends with `perl` before the build,
  and carries 344 `Patch:` lines to match.
- **Debian moves configuration and web content only.** It keeps
  upstream's `/usr/lib/xymon/{server,client}` binary tree but pulls all
  configuration — both roles' — into `/etc/xymon`, and the static web
  assets into `/usr/share/xymon`.
- **Here, upstream's own symlinks do most of the work.** The tree stays
  as the `--server` build lays it out, and the build's own links
  redirect what must not live in `/usr/lib`: `server/etc → /etc/xymon`,
  `server/web → /etc/xymon/web`, `server/www → /var/lib/xymon/www`,
  `server/tmp → /var/lib/xymon/tmp`. The layout therefore matches
  upstream's documentation while nothing writes inside `/usr/lib`, and
  the spec needs no path rewriting and no patches.

  Those links exist only under the *server* tree
  (`build/Makefile.rules:186-241`); the client tree gets none, and
  `client/Makefile` ships its `tmp` and `logs` as real directories. So
  the spec makes the same moves by hand — `client/etc →
  /etc/xymon-client`, `client/logs → /var/log/xymon`, `client/tmp →
  /var/tmp` — as does Debian, at `debian/rules:96-98`. Three more take
  shipped content out of `/var`: `www/{gifs,help,menu} →
  /usr/share/xymon/…`.

**The `www` tree holds two different kinds of thing**, which is why only
part of it moves. `gifs`, `help` and `menu` never change on a running
host, so they belong in `/usr/share`; `html`, `notes`, `rep`, `snap` and
`wml` ship empty and are written by the daemons, and `xymongen` writes
the generated status pages into `www` itself, so `XYMONWWWDIR` stays
writable in `/var/lib`. Symlinking the static three back keeps every
`/xymon/` URL and on-disk path working, so nothing in `xymonserver.cfg`
or the CGIs learns a second location, and httpd needs no extra
configuration — the generated config already sets `FollowSymLinks` on
the www directory, which is what lets it cross into `/usr/share`.

The `help` link is load-bearing rather than cosmetic: `lib/links.c`
derives that directory by taking `XYMONNOTESDIR`, stripping the last
component and appending `/help`, so it has to resolve wherever the files
actually live.

**Configuration is in `/etc` for both roles.** The server gets there
through upstream's own `server/etc → /etc/xymon`; upstream has no
equivalent for the client, so this packaging adds the matching link.
That keeps `/usr` read-only and shareable as the FHS wants, puts the
most-edited file on a client host (`xymonclient.cfg`, which holds
`XYMSRV`) where an admin would look, and costs nothing at runtime: every
reference to those files, in `clientlaunch.cfg` and the server's
`tasks.cfg` alike, is spelled `$XYMONCLIENTHOME/etc/...` and resolves
through the symlink.

Both of these hand-made moves have upstream proposals that would remove
them — [xymon#414](https://github.com/xymon-monitoring/xymon/pull/414)
(`INSTALLSTATICWWWDIR`) and
[xymon#411](https://github.com/xymon-monitoring/xymon/pull/411)
(`INSTALLCLIENT*DIR`).

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
