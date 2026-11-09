# Deployment strategies: how Xymon packagings split server and client

Upstream's `./configure --server` build always produces the server
*together with* its client tree (`XYMONCLIENTHOME = $(XYMONTOPDIR)/client`),
because the server monitors itself through it. The separate `--client`
build differs only by `-DCLIENTONLY`, which strips server-only code to
shrink the binaries; it adds nothing the server build's client lacks.

A fleet wants one server and many small client-only hosts. So each
packaging must decide what a "client package" is and how it relates to the
server package. Four answers exist.

## Debian: amputate, then re-attach with a dependency

One `--server` build. The client tree is cut out of the `xymon` package,
moved into `xymon-client`, and pulled back at install time by
`Depends: xymon-client`. Every server installs both, so the filesystem
ends up as the build made it; only package ownership differs.

The cost is at runtime. Debian ships two services, `xymon` and
`xymon-client`, and the client one carries a guard so it does not
double-report on a server. Since 4.3.30-4 (trixie) each is a systemd unit
beside its SysV init script. The unit's guard is
`ExecCondition=test ! -x /usr/lib/xymon/server/bin/xymond`; the init
script's is `[ -x /usr/lib/xymon/server/bin/xymond ] && exit 0`. The split
also moves `xymond_client` into the `xymon-client` package (Debian #903614),
leaving a symlink to it in the server tree.

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
the build). Neither depends on nor conflicts with the other: different
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
- **One unit name everywhere.** Both packages ship `xymonlaunch.service`.
  Its `ExecStart` runs `xymonlaunch-run`, which picks the tree by which
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
  applies*, which lets a server's xymond finish its checkpoints. It
  leaves enablement alone, so the host still starts at boot. A
  `systemctl restart` brings the new role up.

Two costs, accepted deliberately: the client tree exists in two packages
*in the repository* (never twice on a host: they conflict), and a role
change is an explicit `dnf swap` rather than automatic. An unversioned
`Obsoletes: xymon-client` would be automatic but would convert every
client host into a server at its next update. The spec's versioned one,
`xymon-client < 4.3.31-1`, only folds the old layout's server pair into
`xymon` (`rpm/xymon.spec:239-246`).

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
`client/` beside each other, and leaves each packager to decide how far
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

Those links exist only under the *server* tree, so the spec makes the
client's by hand: `client/etc → /etc/xymon-client`,
`client/logs → /var/log/xymon`, `client/tmp → /var/tmp`. Three more take
static content out of `/var`: `www/{gifs,help,menu} → /usr/share/xymon/…`.

The `www` tree holds three lifecycles, not two:

| | what | belongs in |
| --- | --- | --- |
| `gifs`, `help`, `menu` | **static**: shipped, never changed on a running host | `/usr/share` |
| `html`, `notes`, `wml` | **persistent** state the daemons write | the writable docroot under `/var/lib` |
| `rep`, `snap` | **regenerable**: on-demand availability reports and snapshots, safe to delete, recreated on the next request | `/var/cache` (FHS) |

This spec moves only the static three, symlinking them back so every
`/xymon/` URL and on-disk path still works and nothing in `xymonserver.cfg`
or the CGIs learns a second location. httpd needs no extra config: the
generated one already sets `FollowSymLinks` on the www directory. The `help`
symlink is load-bearing: up to 4.3.31 the web pages derive the help
directory from `XYMONNOTESDIR` at runtime (`lib/links.c:147`), a coupling
xymon#414 removes.

Each hand-made move has an opt-in upstream equivalent, no-op by default:
`INSTALLSTATICWWWDIR` + `XYMONSTATICWWWDIR`
([xymon#414](https://github.com/xymon-monitoring/xymon/pull/414)) for the
static three and `XYMONCACHEWWWDIR`
([xymon#443](https://github.com/xymon-monitoring/xymon/pull/443)) for
`rep`/`snap`, both merged for 4.3.32 and not yet adopted here;
`INSTALLCLIENT*DIR`
([xymon#411](https://github.com/xymon-monitoring/xymon/pull/411), open)
for the client tree.
[xymon-rpm#109](https://github.com/xymon-monitoring/xymon-rpm/issues/109)
tracks their states.

### Where the static web content should live

This applies only to a packaging that **splits** the tree for the FHS. A
source install, and FreeBSD, leave the static three where the build puts
them, inside `INSTALLWWWDIR` (the `www` tree itself). That is
`INSTALLSTATICWWWDIR`'s no-op default (`= INSTALLWWWDIR`), and it is
correct there, because a self-contained tree has no `/usr`-vs-`/var` line
to honour. When a packaging *does* pull the static three out into
`/usr/share`, the recommended shape, and `INSTALLSTATICWWWDIR` target, is
**`/usr/share/xymon/www`**.

- **`/usr/share`, because the FHS says so.** It defines `/usr/share` as
  read-only, architecture-independent package data, and `/var` as what a
  program writes: exactly the static-vs-generated split. Every Linux
  packaging that splits lands static in `/usr/share` (Debian, this one,
  Terabithia). Only FreeBSD keeps it under its port prefix, because it
  follows BSD `hier(7)` rather than the FHS.
- **A `www` subdir, not a bare directory and not a `static`/`staticwww`
  name.** `/usr/share` already *means* static, so a `static` (or
  `staticwww`) folder says it twice. `www` adds what the location does
  not, "this is the web content", and mirrors the served
  `/var/lib/xymon/www`, so the symlink reads as a clean parallel:
  `/var/lib/xymon/www/gifs → /usr/share/xymon/www/gifs`.

Terabithia nests under `/usr/share/xymon/static` because *its*
`/usr/share/xymon` is the whole server home (`bin`, `cgi-bin`, `etc`, `www`,
…), so it has to namespace. A flat `/usr/share/xymon/{gifs,help,menu}`
(Debian's layout, and what this spec installs today) is fine only while
that directory holds nothing but web content; the `www` subdir leaves it
free for non-web data the package might add later.

The regenerable third's target is **`/var/cache/xymon/www`** (FHS §5.5,
"data that can be regenerated" and "deleted without loss"), reached by
pointing `XYMONCACHEWWWDIR` there and symlinking `www/rep` and `www/snap`
back, as the static three are. This spec keeps them in the `/var/lib`
docroot today.
