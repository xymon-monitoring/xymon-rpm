# Deployment strategies: how Xymon packagings split server and client

Upstream's `./configure --server` build always produces the server
*together with* its client tree (`XYMONCLIENTHOME = $(XYMONTOPDIR)/client`),
because the server monitors itself through it. The separate `--client`
build differs only by `-DCLIENTONLY`, which strips server-only code to
shrink the binaries; it adds nothing the server build's client lacks.

A fleet wants the opposite emphasis: one server, many small client-only
hosts. So each packaging must decide what a "client package" is and how
it relates to the server package. Four answers exist.

## Debian: amputate, then re-attach with a dependency

One `--server` build. The client tree is cut out of the `xymon` package,
moved into `xymon-client`, and pulled back at install time by
`Depends: xymon-client`. Every server installs both, so the filesystem
ends up as the build made it; only package ownership differs.

The cost is at runtime. Debian ships two SysV init scripts (`xymon`,
`xymon-client`), and the client one carries a guard so it does not
double-report on a server: `[ -x /usr/lib/xymon/server/bin/xymond ] &&
exit 0`. The split also moves `xymond_client` into the `xymon-client`
package (Debian #903614), leaving a symlink to it in the server tree.

## Terabithia: self-contained server, standalone client

Two builds (a client build set aside, then a full server build). The
server package embeds its own client and declares no dependency on
`xymon-client`. The exclusion is *implicit*: both ship `/usr/bin/xymon`,
`/usr/sbin/xymonlaunch` and friends, so rpm refuses coinstallation with
raw file-conflict errors. Both use the same unit name, so no runtime
guard is needed.

The architecture is right, but the second build is redundant, the
exclusion has no clean metadata, and the scriptlets carry literal
"this is a hack" comments.

## FreeBSD: two ports, no relationship

Two independent ports, two builds. `xymon-client` is a real
`CLIENTONLY=yes` build; `xymon-server` runs a server build with the
client removed at source (the port drops `client`/`install-client` from
the build). Neither depends on nor conflicts with the other — different
paths, co-installable, separate rc scripts. Nothing prevents both from
running, or a server from running with no client; coordination is the
admin's job.

## This packaging: self-contained server, one build, explicit conflict

Terabithia's architecture at Debian's build cost, with the sharp edges
filed off:

- **One `--server` build.** Its client tree is complete, so both
  packages ship from it and their shared files are byte-identical.
- **`xymon` is the whole build output** (server plus embedded client)
  and needs nothing. **`xymon-client` is that same client tree packaged
  alone** for non-server hosts.
- **`Conflicts: xymon-client`** puts the exclusion in metadata:
  `dnf install xymon` on a client host fails with a clear message.
- **One unit name everywhere.** Both packages ship `xymonlaunch.service`;
  its `ExecStart` runs `xymonlaunch-run`, which picks the tree by which
  role's drop-in is present and execs `xymoncmd xymonlaunch --no-daemon`
  in the foreground, giving `Type=simple` a process to supervise. What
  differs between roles rides in a drop-in shipped only by that role's
  package: the server protects xymond's children on stop
  (`KillMode=process`, `SendSIGKILL=no`), the client waits for
  `network-online.target` at boot. Double-reporting is unrepresentable,
  so no guard exists.
- **Role changes are one transaction.** Scriptlets detect a swap by the
  other role's drop-in already being on disk (installs precede erases).
  The departing package stops the service *while its own drop-in still
  applies* — that is what lets a server's xymond finish its checkpoints —
  and leaves enablement alone, so the host still starts at boot. A
  `systemctl restart` brings the new role up.

Two costs, accepted deliberately: the client tree exists in two packages
*in the repository* (never twice on a host — they conflict), and a role
change is an explicit `dnf swap` rather than automatic. `Obsoletes:`
would be automatic but would convert every client host into a server at
its next update.

## Side by side

| | Debian | Terabithia | FreeBSD | here |
| --- | --- | --- | --- | --- |
| Builds | 1 | 2 | 2 | 1 |
| Server self-contained | no | yes | no (ships no client) | yes |
| Server ↔ client relation | `Depends` | implicit conflict | none | explicit `Conflicts:` |
| Server on a client host | layers on top | fails, ugly errors | coexists silently | fails, clear message |
| Units | 2 + guard | 1 | 2 rc scripts | 1, no guard |
| Double-reporting | guarded | unrepresentable | possible | unrepresentable |
| Role change | maintainer scripts | scriptlet hacks | manual | defined `dnf swap` |

## Where the files land

Upstream installs everything under one `XYMONTOPDIR`, with `server/` and
`client/` beside each other, and leaves each packager to decide how much
to bend towards the FHS.

| | here | Debian | Terabithia | FreeBSD (`…` = `${PREFIX}/www`) |
| --- | --- | --- | --- | --- |
| Server config | `/etc/xymon/` | `/etc/xymon/` | `/etc/xymon/` | `…/xymon/server/etc/` |
| Client config | `/etc/xymon-client/` | `/etc/xymon/` | `/etc/xymon-client/` | `…/xymon/client/etc/` |
| Server binaries | `/usr/lib/xymon/server/bin/` | same | `/usr/libexec/xymon/`, `/usr/sbin/` | `…/xymon/server/bin/` |
| Client binaries | `/usr/lib/xymon/client/bin/` | same | `/usr/libexec/xymon-client/` | `…/xymon/client/bin/` |
| Static web assets | `/usr/share/xymon/` | `/usr/share/xymon/` | `/usr/share/xymon/static/` | `…/xymon/server/www/` |
| Generated pages | `/var/lib/xymon/www/` | `/var/lib/xymon/www/` | `/var/www/xymon/` | `…/xymon/server/www/` |
| Server data / logs | `/var/lib/xymon/`, `/var/log/xymon/` | same | same | `…/xymon/data/`, `…/data/logs/` |

Terabithia rewrites the layout wholesale (hence its `perl` path rewrites
and 344 `Patch:` lines). Debian keeps upstream's `/usr/lib/xymon` binary
tree but moves all config into `/etc/xymon` and static assets into
`/usr/share/xymon`.

**Here, upstream's own symlinks do most of the work.** The tree stays as
the `--server` build lays it out, and the build's links redirect what
must not live in `/usr/lib`: `server/etc → /etc/xymon`,
`server/www → /var/lib/xymon/www`, `server/tmp → /var/lib/xymon/tmp`.
The layout matches upstream's docs, nothing writes inside `/usr/lib`,
and the spec needs no path rewriting or patches.

Those links exist only under the *server* tree; the client tree gets
none, so the spec makes the matching moves by hand:
`client/etc → /etc/xymon-client`, `client/logs → /var/log/xymon`,
`client/tmp → /var/tmp`. Three more take static content out of `/var`:
`www/{gifs,help,menu} → /usr/share/xymon/…`.

The `www` tree actually holds three lifecycles, not two. `gifs`, `help`
and `menu` are **static** — shipped, never changed on a running host — so
they belong in `/usr/share`. `html`, `notes` and `wml` are **persistent**
state the daemons write, so they stay in the writable docroot under
`/var/lib`. `rep` and `snap` are **regenerable** — on-demand availability
reports and snapshots, safe to delete and recreated on the next request,
which is what the FHS puts in `/var/cache`. This spec moves only the
static three today, symlinking them back so every `/xymon/` URL and
on-disk path still works — nothing in `xymonserver.cfg` or the CGIs learns
a second location, and httpd needs no extra config because the generated
one already sets `FollowSymLinks` on the www directory. `rep` and `snap`
stay in the `/var/lib` docroot for now. The `help` link is load-bearing:
`lib/links.c` derives that directory from `XYMONNOTESDIR`, so it must
resolve wherever the files live — a coupling xymon#414 removes (below).

Each hand-made move has an upstream proposal to retire it — all opt-in,
no-op by default:

- **static** (`gifs`/`help`/`menu`) —
  [xymon#414](https://github.com/xymon-monitoring/xymon/pull/414): both halves,
  `INSTALLSTATICWWWDIR` (install placement) and `XYMONSTATICWWWDIR` (runtime, so
  `lib/links.c` resolves `help` from the static dir, not from `XYMONNOTESDIR`).
  [This repo's #4](https://github.com/xymon-monitoring/xymon-rpm/pull/4) is the
  consuming side — sets `INSTALLSTATICWWWDIR=%{_datadir}/xymon` and drops the
  `mv`+`ln` loop (draft until #414 lands; CI-verified against `pr/414`).
- **client** (`etc`/`logs`/`tmp`) —
  [xymon#411](https://github.com/xymon-monitoring/xymon/pull/411):
  `INSTALLCLIENT*DIR`.
- **regenerable** (`rep`/`snap`) —
  [xymon#443](https://github.com/xymon-monitoring/xymon/pull/443):
  `XYMONCACHEWWWDIR`, the runtime knob for a `/var/cache` move this spec has
  not made yet (target below).

### Where the static web content should live

This applies only to a packaging that **splits** the tree for the FHS. A
source install — and FreeBSD — leave the static three where the build
puts them, inside `INSTALLWWWDIR` (the `www` tree itself): that is
`INSTALLSTATICWWWDIR`'s no-op default (`= INSTALLWWWDIR`), and it is
correct there, because a self-contained tree has no `/usr`-vs-`/var` line
to honour. When a packaging *does* pull the static three out into
`/usr/share`, the recommended shape is **`/usr/share/xymon/www`**.

- **`/usr/share`, because the FHS says so.** It defines `/usr/share` as
  read-only, architecture-independent package data, and `/var` as what a
  program writes — which is exactly the static-vs-generated split. Every
  Linux packaging that splits lands static in `/usr/share` (Debian, this
  one, Terabithia); only FreeBSD keeps it under its port prefix, and only
  because it follows BSD `hier(7)` rather than the FHS.
- **A `www` subdir — not a bare directory, and not a `static`/`staticwww`
  name.** `/usr/share` already *means* static, so naming the folder
  `static` (or `staticwww`) states "static" twice. `www` adds the one thing
  the location does not — "this is the web content" — and it mirrors the
  served `/var/lib/xymon/www`, so the symlink reads as a clean parallel:
  `/var/lib/xymon/www/gifs → /usr/share/xymon/www/gifs`. It also keeps
  `/usr/share/xymon` free for any non-web data the package might add later.

For contrast: Terabithia nests under `/usr/share/xymon/static` because *its*
`/usr/share/xymon` is the whole server home (`bin`, `cgi-bin`, `etc`, `www`,
…), so it has to namespace. A flat `/usr/share/xymon/{gifs,help,menu}` —
Debian's layout, and what this spec installs today — is fine only while that
directory holds nothing but web content; the `www` subdir is the more
self-documenting and future-proof form, and the recommended target for the
`INSTALLSTATICWWWDIR` the split will eventually use.

The regenerable third's target is **`/var/cache/xymon/www`** — FHS §5.5,
"data that can be regenerated" and "deleted without loss" — reached by
pointing `XYMONCACHEWWWDIR` there and symlinking `www/rep`, `www/snap` back,
as the static three are. This spec keeps them in the `/var/lib` docroot today.

## Repositories: snapshots vs tagged releases

CI (`.github/workflows/build.yml`) builds two kinds of package from the
same spec (`rpm/baseversion` sets the base, currently 4.3.31):

- **Snapshots** of upstream `main`, versioned
  `X.Y.Z-0.<date>git<sha>.<pkgdate>p<pkgsha>`. The first pair identifies
  the upstream commit, the second the last packaging commit, so a
  packaging-only fix still mints a new NEVRA. The leading `-0.` sorts
  below the eventual `-1`, so snapshot users are absorbed cleanly when
  the release lands. A nightly cron rebuild of `main` is the drift
  detector: an upstream path or flag change turns it red the next day.
- **Releases** built from an exact `rel-*` tag as `X.Y.Z-1`. A published
  NEVRA is immutable, so a packaging-only re-release of a tag bumps
  `releasenum` to ship `-2`.

Only genuine builds of `main` or a `rel-*` tag publish to the signed
gh-pages repository; pull requests and one-off branch builds never do.

## Migrating from the old layout

Before this design, `xymon` required `xymon-client` and a separate
`xymon-client.service` carried a `Conflicts=` guard.

- **Client-only hosts** upgrade normally: the client package's `%post`
  carries enablement and any running instance over to
  `xymonlaunch.service`.
- **Server hosts** have both packages, which the new `xymon` conflicts
  with, so the upgrade is one explicit `dnf swap xymon-client xymon`.
  Until it runs the conflict makes the whole `dnf upgrade` unsolvable,
  so an unattended updater silently stops. Acceptable only because this
  packaging is experimental; a stable release would need a `%triggerun`
  migration or a transitional package.
