# Where things live, and how to run them

A host is either a **server** (`xymon`) or a **client**
(`xymon-client`); the packages conflict, so nothing is ever both. Both
run the same service, `xymonlaunch.service`, so every command below is
identical on every host — only the files differ.

A server also monitors *itself*, through a client tree that is part of
the server package and driven from the server's own `tasks.cfg`, not by
a second service. Finding client files on a server is normal.

## The layout

Five roots, each with one job: `/etc` configuration, `/usr/lib`
programs, `/usr/share` static content, `/var/lib` the server's data,
`/var/log` logs.

A **server host** (`xymon`):

```
/etc/xymon/                     server configuration
├── hosts.cfg                   what is monitored
├── tasks.cfg                   what the server runs (incl. its own client)
├── xymonserver.cfg             server identity, paths, URLs
├── alerts.cfg analysis.cfg graphs.cfg rrddefinitions.cfg …
├── hosts.d/ alerts.d/ tasks.d/ …     drop-ins for the above
├── web/                        page headers, footers, forms
└── xymonpasswd  xymongroups    web logins (apache-owned)
/etc/xymon-client/              the embedded client's config
/etc/sysconfig/xymonlaunch      XYMONLAUNCHOPTS
/etc/httpd/conf.d/xymon-apache.conf   serves /xymon, /xymon-cgi/, /xymon-seccgi/
/usr/lib/xymon/
├── server/bin/                 xymond, xymongen, xymonnet, xymond_*
├── cgi-bin/  cgi-secure/       the web CGIs (the second needs a login)
└── client/                     the embedded client (see below)
/usr/share/xymon/               gifs/ help/ menu/ — static web content
/var/lib/xymon/                 rrd/ hist/ histlogs/ hostdata/ data/
│                               acks/ disabled/
└── www/                        what xymongen writes, plus rep/ snap/
                                notes/ html/, and symlinks to the
                                static content above
/var/log/xymon/                 xymonlaunch.log xymond.log xymonclient.log …
/usr/bin/xymon  /usr/bin/xymoncmd  /usr/sbin/xymonlaunch    for typing by hand
```

A **client host** (`xymon-client`) has only the client half:

```
/etc/xymon-client/              xymonclient.cfg  ← XYMSRV lives here
│                               clientlaunch.cfg  localclient.cfg
/etc/sysconfig/xymon-client     CLIENTHOSTNAME, CLIENTOS
/etc/logrotate.d/xymon          (both roles ship this)
/usr/lib/xymon/client/
├── bin/                        xymonclient.sh, xymonclient-linux.sh,
│                               logfetch, clientupdate, msgcache, xymonlaunch
├── ext/  local/                your own extension scripts
├── etc  -> /etc/xymon-client   upstream's $XYMONCLIENTHOME/etc paths still work
├── logs -> /var/log/xymon
└── tmp  -> /var/tmp
/var/log/xymon/                 clientlaunch.log …
```

On **both**, one service and the drop-in naming its role:

```
/usr/lib/systemd/system/xymonlaunch.service
/usr/lib/systemd/system/xymonlaunch.service.d/
└── server.conf   (server host)   |   client.conf   (client host)
```

Nothing writes inside `/usr/lib`: the symlinks above, and upstream's own
(`server/etc → /etc/xymon`, `server/www → /var/lib/xymon/www`, `server/tmp
→ /var/lib/xymon/tmp`), redirect everything mutable into `/etc`, `/var`
and `/tmp`. `/run/xymon` is created by tmpfiles and unused — see the
README's known gaps.

## Running the service

```sh
systemctl status xymonlaunch          # up? which role?
systemctl start|stop|restart xymonlaunch
journalctl -u xymonlaunch -f
```

The real logs are files, not the journal: `/var/log/xymon/`. On a server
begin with `xymonlaunch.log`, `xymond.log` and `xymonclient.log` (its
own client run); on a client, `clientlaunch.log`.

`systemctl reload` sends `SIGHUP`. `xymonlaunch` acts on it — rereading
`tasks.cfg` and reopening its own log — but does not pass it to the
daemons it started, so use `restart` to reach those until upstream
[xymon#172](https://github.com/xymon-monitoring/xymon/pull/172) merges.

To see which role is running (the client names `clientlaunch.cfg`, the
server does not):

```sh
systemctl show -p MainPID --value xymonlaunch | xargs -I{} tr '\0' ' ' < /proc/{}/cmdline
```

## Client tasks

**Point it at the server.** Set `XYMSRV` in
`/etc/xymon-client/xymonclient.cfg` — it ships as `127.0.0.1`, which is
right only on the server itself — then restart. For several servers,
`XYMSERVERS="ip1 ip2"` with `XYMSRV="0.0.0.0"`.

**Enable it at boot.** A fresh client does not enable itself, because
it would report to that unconfigured default: `systemctl enable --now
xymonlaunch`.

**Set the reported name.** `CLIENTHOSTNAME` in
`/etc/sysconfig/xymon-client` must match the name in the server's
`hosts.cfg`, or the data arrives as a ghost. `CLIENTOS` overrides the
collector script chosen for the OS.

**Add a check.** A script in `/usr/lib/xymon/client/ext/` plus a
`[name]` stanza in `clientlaunch.cfg`.

**Analyse locally** instead of on the server: install
`xymon-client-local`, put rules in `localclient.cfg`, add `--local` to
the client's entry in `clientlaunch.cfg`.

## Server tasks

**Add a host.** `/etc/xymon/hosts.cfg` (or a file in `hosts.d/`), then
restart. The name must match what the client reports.

**Web access.** The UI is `http://<server>/xymon/`. The authenticated
CGIs read `/etc/xymon/xymonpasswd`, which ships empty and
`apache`-owned, so nobody can log in until you add someone:

```sh
htpasswd /etc/xymon/xymonpasswd alice     # -c only for the first user
```

**Alerts** live in `alerts.cfg`, **thresholds** in `analysis.cfg`,
**graphs** in `graphs.cfg` and `rrddefinitions.cfg`; each has a `.d/`
directory if you prefer drop-ins.

**Server identity** is `xymonserver.cfg`. `%post` rewrites
`XYMONSERVERHOSTNAME` to the real hostname on first install; change it
there if you rename the host.

**Its own monitoring** is the `[xymonclient]` stanza in `tasks.cfg`,
which runs the embedded client every 5 minutes against
`/etc/xymon-client/xymonclient.cfg`. That is why a server's `XYMSRV`
stays `127.0.0.1` — it reports to itself. Do not "fix" it.

## Changing a host's role

```sh
dnf swap xymon-client xymon     # promote a client to the server
dnf swap xymon xymon-client     # demote a server to a client
systemctl restart xymonlaunch
```

The swap stops the old role cleanly and keeps the unit enabled; the
restart brings the new one up. **After a demotion, set `XYMSRV`** — the
former server's config still says `127.0.0.1`, and a client reporting
to a server that no longer exists says nothing about it.

## When something is wrong

| Symptom | Look here |
| --- | --- |
| Host missing from the web UI | in `hosts.cfg`? `CLIENTHOSTNAME` matching? unit running? |
| Host shows as a "ghost" | the reported name differs from `hosts.cfg` |
| Client runs, no data arrives | `XYMSRV`; port 1984 reachable; `clientlaunch.log` |
| Sections empty (disk, ports, ifstat) | `net-tools` missing, or the collector failed — `clientlaunch.log` |
| Web pages 500 | `xymonpasswd` missing or not `apache`-owned; httpd error log |
| Nothing running after a swap | `systemctl restart xymonlaunch` — the swap starts nothing |
| `dnf upgrade` fails on a server | pre-conflict layout: `dnf swap xymon-client xymon` |

How this packaging compares with Debian's, Terabithia's and FreeBSD's:
[deployment-strategies.md](deployment-strategies.md).
