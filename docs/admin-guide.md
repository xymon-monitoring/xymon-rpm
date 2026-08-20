# Where things live, and how to run them

A host is either a **server** (`xymon`) or a **client** (`xymon-client`);
the two packages conflict, so nothing is ever both. Both roles run the
same service, `xymonlaunch.service`, so every command below is the same
on every host — only the files differ.

A server also monitors *itself*. It does that through a client tree
installed as part of the server package, driven from the server's own
`tasks.cfg`, not from a second service. So on a server you will find
client files at the same paths a client host has, and that is normal.

## The layout

Everything lives under four roots: `/etc` for configuration, `/usr/lib`
for programs, `/var/lib` for the server's data, `/var/log` for logs.

A **server host** (`xymon`):

```
/etc/xymon/                     all server configuration
├── hosts.cfg                   what is monitored
├── tasks.cfg                   what the server runs (incl. its own client)
├── xymonserver.cfg             server identity, paths, URLs
├── alerts.cfg analysis.cfg graphs.cfg rrddefinitions.cfg …
├── hosts.d/ alerts.d/ analysis.d/ tasks.d/ …    drop-ins for the above
├── web/                        page headers, footers, forms
└── xymonpasswd  xymongroups    web logins (apache-owned)
/etc/sysconfig/xymonlaunch      launcher options
/etc/httpd/conf.d/xymon-apache.conf
/usr/lib/xymon/
├── server/bin/                 xymond, xymongen, xymonnet, xymond_*
├── cgi-bin/  cgi-secure/       the web CGIs
└── client/                     ← the embedded client, see below
/etc/xymon-client/              its config (same as a client host)
/usr/share/xymon/               gifs/ help/ menu/   static web content
/var/lib/xymon/                 rrd/ hist/ histlogs/ hostdata/ data/
│                               acks/ disabled/
└── www/                        pages xymongen writes, plus rep/ snap/
                                notes/ html/ — and symlinks to the
                                static content above
/var/log/xymon/                 xymonlaunch.log xymond.log xymonclient.log …
```

A **client host** (`xymon-client`) has only the client tree — the same
one, at the same path, that a server also carries:

```
/etc/xymon-client/              xymonclient.cfg  ← XYMSRV lives here
│                               clientlaunch.cfg  localclient.cfg
/etc/sysconfig/xymon-client     CLIENTHOSTNAME, CLIENTOS
/etc/logrotate.d/xymon
/usr/lib/xymon/client/
├── bin/                        xymonclient.sh, xymonclient-linux.sh,
│                               logfetch, clientupdate, msgcache, xymonlaunch
├── etc  -> /etc/xymon-client   so upstream's $XYMONCLIENTHOME/etc paths work
├── ext/  local/                your own extension scripts
├── logs -> /var/log/xymon      nothing writes inside /usr/lib
└── tmp  -> /var/tmp
/var/log/xymon/                 clientlaunch.log …
```

And on **both**, the one service plus its role drop-in:

```
/usr/lib/systemd/system/xymonlaunch.service
/usr/lib/systemd/system/xymonlaunch.service.d/
└── server.conf   (server host)   |   client.conf   (client host)
```

The shape to remember: a client host is the client subtree of a server
host. Same paths, same files — a server just has the server tree, the
web layer and the data directories in addition.

## What each path is for

Paths are identical in both roles; the "role" column says who ships it.

| Path | Contents | Role |
| --- | --- | --- |
| `/etc/xymon/` | server configuration: `hosts.cfg`, `tasks.cfg`, `xymonserver.cfg`, `alerts.cfg`, `analysis.cfg`, `graphs.cfg`, … | server |
| `/etc/xymon/*.d/` | drop-in dirs for the same: `hosts.d`, `alerts.d`, `analysis.d`, `combo.d`, `graphs.d`, `rrddefinitions.d`, `tasks.d` | server |
| `/etc/xymon/web/` | page headers, footers and forms for the web UI | server |
| `/etc/xymon/xymonpasswd`, `xymongroups` | web login credentials, owned by `apache` | server |
| `/etc/httpd/conf.d/xymon-apache.conf` | serves `/xymon`, `/xymon-cgi/`, `/xymon-seccgi/` | server |
| `/etc/sysconfig/xymonlaunch` | options for the launcher (`XYMONLAUNCHOPTS`) | server |
| `/etc/sysconfig/xymon-client` | client hostname/OS overrides (`CLIENTHOSTNAME`, `CLIENTOS`) | client |
| `/etc/logrotate.d/xymon` | rotation for everything in `/var/log/xymon` | both |
| `/usr/lib/xymon/server/bin/` | the server programs: `xymond`, `xymongen`, `xymonnet`, `xymond_*`, the CGIs' backends | server |
| `/usr/lib/xymon/cgi-bin/`, `cgi-secure/` | web CGIs (the second needs authentication) | server |
| `/usr/lib/xymon/client/bin/` | the collectors: `xymonclient.sh`, `xymonclient-linux.sh`, `logfetch`, `clientupdate`, `msgcache` | both |
| `/etc/xymon-client/` | `xymonclient.cfg` (holds `XYMSRV`), `clientlaunch.cfg`, `localclient.cfg`; reachable as `/usr/lib/xymon/client/etc` too | both |
| `/usr/lib/xymon/client/ext/`, `local/` | your own client extension scripts | both |
| `/usr/lib/systemd/system/xymonlaunch.service` | the one service, identical in both packages | both |
| `…/xymonlaunch.service.d/server.conf` \| `client.conf` | the per-role differences | one each |
| `/usr/share/xymon/` | static web content: `gifs/`, `help/`, `menu/` (symlinked into `www/`) | server |
| `/var/lib/xymon/` | server state: `rrd/`, `hist/`, `histlogs/`, `hostdata/`, `data/`, `acks/`, `disabled/`, `www/` | server |
| `/var/log/xymon/` | all logs, both roles (`/usr/lib/xymon/client/logs` is a symlink here) | both |
| `/run/xymon/` | runtime dir created by tmpfiles (not yet used — see the README's known gaps) | both |
| `/usr/bin/xymon`, `/usr/bin/xymoncmd`, `/usr/sbin/xymonlaunch` | conveniences on `$PATH` for typing by hand | server |

The client tree's `tmp` is a symlink to `/var/tmp` and `logs` to
`/var/log/xymon`, so nothing writes inside `/usr/lib`. The server tree
is redirected the same way by upstream's own links: `server/etc →
/etc/xymon`, `server/www → /var/lib/xymon/www`, `server/tmp →
/var/lib/xymon/tmp`.

Configuration is in `/etc` for both roles: `/etc/xymon/` for the server
and `/etc/xymon-client/` for the client. Upstream's own symlink does
that for the server (`server/etc → /etc/xymon`) and this packaging adds
the matching one for the client (`client/etc → /etc/xymon-client`), so
paths written the upstream way still resolve.

## Running the service

Same on every host:

```sh
systemctl status xymonlaunch          # is it up, and which role
systemctl start|stop|restart xymonlaunch
journalctl -u xymonlaunch -f          # what systemd saw
```

To see which role is actually running, look at what the launcher was
started as — the client role names `clientlaunch.cfg`, the server role
does not:

```sh
systemctl show -p MainPID --value xymonlaunch | xargs -I{} tr '\0' ' ' < /proc/{}/cmdline
```

`systemctl reload` sends `SIGHUP`, which `xymonlaunch` does not yet
relay to its children; use `restart` until upstream
[xymon#172](https://github.com/xymon-monitoring/xymon/pull/172) merges.

Real logs are files, not the journal: `/var/log/xymon/`. On a server
start with `xymonlaunch.log`, `xymond.log` and `xymonclient.log` (the
server's own client run); on a client, `clientlaunch.log`.

## Client tasks

**Point a client at its server.** Edit `XYMSRV` in
`/etc/xymon-client/xymonclient.cfg` (it ships as `127.0.0.1`,
which is correct only on the server itself), then
`systemctl restart xymonlaunch`. For several servers, set
`XYMSERVERS="ip1 ip2"` and `XYMSRV="0.0.0.0"`.

**Change the name a host reports as.** Set `CLIENTHOSTNAME` in
`/etc/sysconfig/xymon-client` — the name must match the one in the
server's `hosts.cfg`, or the data arrives as a ghost. `CLIENTOS` in the
same file overrides the collector script chosen for the OS.

**Enable the client at boot.** A fresh client install deliberately does
not enable itself, because it would report to the unconfigured default
address:

```sh
systemctl enable --now xymonlaunch
```

**Add your own check.** Drop a script in
`/usr/lib/xymon/client/ext/` and add a `[name]` stanza to
`clientlaunch.cfg` (`%config(noreplace)`, so upgrades keep it).

**Analyse thresholds locally** instead of on the server: install
`xymon-client-local`, put your rules in `localclient.cfg`, and add
`--local` to the client's entry in `clientlaunch.cfg`.

## Server tasks

**Add a host to monitoring.** Put it in `/etc/xymon/hosts.cfg` (or a
file in `hosts.d/`), then `systemctl restart xymonlaunch`. The name
there must match what the client reports.

**Web access.** The UI is at `http://<server>/xymon/`. Credentials for
the authenticated CGIs live in `/etc/xymon/xymonpasswd`:

```sh
htpasswd /etc/xymon/xymonpasswd alice     # -c only for the very first user
```

The file ships empty and `apache`-owned, so nobody can log in until you
add someone.

**Alerts** go in `/etc/xymon/alerts.cfg`, **thresholds** in
`analysis.cfg`, **graph definitions** in `graphs.cfg` and
`rrddefinitions.cfg`. Each has a matching `.d/` directory if you prefer
drop-ins.

**What the server runs** is `/etc/xymon/tasks.cfg` — one stanza per
daemon. Its `[xymonclient]` stanza is how the server monitors itself:

```
[xymonclient]
	ENVFILE /usr/lib/xymon/client/etc/xymonclient.cfg   # → /etc/xymon-client/
	CMD /usr/lib/xymon/client/bin/xymonclient.sh
	LOGFILE $XYMONSERVERLOGS/xymonclient.log
	INTERVAL 5m
```

That is also why a server's `XYMSRV` stays `127.0.0.1`: it reports to
itself. Do not "fix" it.

**Server identity** (hostname, URLs, paths) lives in
`xymonserver.cfg`. The package rewrites `XYMONSERVERHOSTNAME` to the
real hostname on first install; if you rename the host, change it there.

## Changing a host's role

The packages conflict, so a role change is a swap, not an install:

```sh
dnf swap xymon-client xymon     # promote a client to the server
dnf swap xymon xymon-client     # demote a server to a client
systemctl restart xymonlaunch
```

The swap stops the old role cleanly and keeps the unit's enabled state;
the restart brings the new one up. **After a demotion, set `XYMSRV`** —
the former server's `xymonclient.cfg` still says `127.0.0.1`, and a
client pointed at a server that no longer exists reports into the void
without any error.

## When something is wrong

| Symptom | Look here |
| --- | --- |
| Host missing from the web UI | is it in `hosts.cfg`; does `CLIENTHOSTNAME` match; is the client's unit running |
| Host shows as a "ghost" | the name the client reports differs from `hosts.cfg` |
| Client runs but no data arrives | `XYMSRV` in `xymonclient.cfg`; port 1984 reachable; `/var/log/xymon/clientlaunch.log` |
| Sections empty (disk, ports, ifstat) | `net-tools` missing, or the collector failed — see `clientlaunch.log` |
| Web pages 500 | `/etc/xymon/xymonpasswd` missing or not `apache`-owned; httpd error log |
| Unit dead right after a swap | run `systemctl restart xymonlaunch`; the swap intentionally leaves nothing running |
| `dnf upgrade` fails on a server | old layout with both packages installed — run `dnf swap xymon-client xymon` |

For how this packaging differs from Debian's, Terabithia's and
FreeBSD's, see [deployment-strategies.md](deployment-strategies.md).
