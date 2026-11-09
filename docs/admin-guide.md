# Where things live, and how to run them

A host is either a **server** (`xymon`) or a **client** (`xymon-client`);
the packages conflict, so nothing is ever both. Both run the same service,
`xymonlaunch.service`, so every command below is identical everywhere; only
the files differ. A server also monitors *itself* through an embedded client
tree driven from its own `tasks.cfg`, so client files on a server are
normal.

## The layout

Five roots: `/etc` config, `/usr/lib` programs, `/usr/share` static web
content, `/var/lib` server data, `/var/log` logs.

A **server host** (`xymon`):

```
/etc/xymon/                     server config
├── hosts.cfg                   what is monitored
├── tasks.cfg                   what the server runs (incl. its own client)
├── xymonserver.cfg             server identity, paths, URLs
├── alerts.cfg analysis.cfg graphs.cfg rrddefinitions.cfg …
├── hosts.d/ alerts.d/ tasks.d/ …    drop-ins
├── web/                        page headers, footers, forms
└── xymonpasswd  xymongroups    web logins (apache-owned)
/etc/xymon-client/              the embedded client's config
/etc/sysconfig/xymonlaunch      XYMONLAUNCHOPTS
/etc/httpd/conf.d/xymon-apache.conf   serves /xymon, /xymon-cgi/, /xymon-seccgi/
/usr/lib/xymon/
├── server/bin/                 xymond, xymongen, xymonnet, xymond_*
├── cgi-bin/  cgi-secure/       web CGIs (cgi-secure needs a login)
└── client/                     the embedded client
/usr/share/xymon/               gifs/ help/ menu/ — static web content
/var/lib/xymon/                 rrd/ hist/ histlogs/ hostdata/ acks/ …
└── www/                        what xymongen writes, + symlinks to the static content and to rep/ snap/
/var/cache/xymon/www/           rep/ snap/ — on-demand reports and snapshots, safe to delete
/var/log/xymon/                 xymonlaunch.log xymond.log xymonclient.log …
/usr/bin/xymon  /usr/bin/xymoncmd  /usr/sbin/xymonlaunch   for typing by hand
```

A **client host** (`xymon-client`) has only the client half:

```
/etc/xymon-client/              xymonclient.cfg (XYMSRV), clientlaunch.cfg, localclient.cfg
├── clientlaunch.d/             drop-ins: extra tasks
└── xymonclient.d/              drop-ins: extra client settings
/etc/sysconfig/xymon-client     MACHINEDOTS, SERVEROSTYPE
/etc/logrotate.d/xymon          (both roles ship this)
/usr/lib/xymon/client/bin/      xymonclient.sh, logfetch, clientupdate, xymonlaunch …
/usr/lib/xymon/client/ext/  local/   your own extension scripts
/var/log/xymon/                 xymonclient.log …
```

The service and its role drop-in, on both:

```
/usr/lib/systemd/system/xymonlaunch.service
/usr/lib/systemd/system/xymonlaunch.service.d/{server,client}.conf
```

Nothing writes inside `/usr/lib`: symlinks redirect everything mutable into
`/etc` and `/var` (the client's `tmp` into `/var/tmp`). `/run/xymon`, created
by tmpfiles, holds the server's pidfiles and `xymond_rrd`'s control sockets
from 4.3.32 (snapshots built since 8 Nov 2026). A 4.3.31 server keeps them in
`/var/log/xymon` and `/var/lib/xymon/tmp`.

## Running the service

```sh
systemctl status xymonlaunch
systemctl start|stop|restart xymonlaunch
journalctl -u xymonlaunch -f
```

The real logs are files under `/var/log/xymon/`: on a server, start with
`xymonlaunch.log`, `xymond.log` and `xymonclient.log`; on a client,
`xymonclient.log`. A client's `xymonlaunch` runs without `--log`, so its own
messages go to the journal.

`systemctl reload` sends `SIGHUP`. `xymonlaunch` acts on it (rereads
`tasks.cfg`, reopens its log) but does not pass it to the daemons it started.
Use `restart` to reach those until upstream
[xymon#172](https://github.com/xymon-monitoring/xymon/pull/172) merges.

To tell which role is running (only the client names `clientlaunch.cfg`):

```sh
tr '\0' ' ' < /proc/"$(systemctl show -p MainPID --value xymonlaunch)"/cmdline; echo
```

## Client tasks

- **Point it at the server.** Set `XYMSRV` in
  `/etc/xymon-client/xymonclient.cfg` (ships as `127.0.0.1`, right only on the
  server itself), then restart. For several servers, use
  `XYMSERVERS="ip1 ip2"` with `XYMSRV="0.0.0.0"`.
- **Enable at boot.** A fresh client does not enable itself (it would report
  to the unconfigured default): `systemctl enable --now xymonlaunch`.
- **Set the reported name.** `MACHINEDOTS` in `/etc/sysconfig/xymon-client`
  must match the name in the server's `hosts.cfg`, or data arrives as a ghost.
  `SERVEROSTYPE` overrides the OS collector. Both default from `uname` when
  unset.
- **Add a check.** A script in `/usr/lib/xymon/client/ext/` plus a `[name]`
  stanza in a file of your own under `/etc/xymon-client/clientlaunch.d/`,
  not in `clientlaunch.cfg`. That file is `%config(noreplace)`: once you edit
  it, rpm keeps your copy, so nothing upstream changes in it reaches the host.
  The day it does change, you get a `.rpmnew` to merge by hand. A drop-in
  belongs to you, and the shipped file keeps upgrading.
- **Analyse locally.** Install `xymon-client-local`, put rules in
  `localclient.cfg`, add `--local` to the client's entry in `clientlaunch.cfg`.

## Server tasks

- **Add a host.** Edit `/etc/xymon/hosts.cfg` (or a file in `hosts.d/`), then
  restart. The name must match what the client reports, and **the address must
  be unique**: Xymon keys hosts by address, so a second entry for an address
  already listed is ignored. Rename the existing entry instead. An unmatched
  host still shows green from network tests while its client data is never
  analysed.
- **Web access.** The UI is `http://<server>/xymon/`. firewalld's default
  zone does not admit HTTP, so with firewalld running, let browsers in. If
  httpd serves the UI over TLS, add `--add-service=https` too; `mod_ssl` is
  not pulled in by these packages.

  ```sh
  firewall-cmd --permanent --add-service=http && firewall-cmd --reload
  ```

  The authenticated CGIs read `/etc/xymon/xymonpasswd`, which ships empty and
  `apache`-owned. Add a user before anyone can log in:

  ```sh
  htpasswd /etc/xymon/xymonpasswd alice     # -c only for the first user
  ```

- **Let clients in.** Clients report to port 1984. firewalld ships a service
  for it, `bb`, on every release these packages are built for. With firewalld
  running:

  ```sh
  firewall-cmd --permanent --add-service=bb && firewall-cmd --reload
  ```

- **Clients over TLS** (from 4.3.32; snapshots and previews have it now).
  xymond takes TLS on a port of its own, 1985 by default, once it has a
  `--tls-listen` address on its `[xymond]` command in `tasks.cfg`, and a
  certificate and key: `/etc/xymon/tls/xymond.pem` and `xymond.key` unless
  `xymonserver.cfg` names others. xymon-tls(7) has the steps. firewalld has no
  service for 1985, so open the port itself:

  ```sh
  firewall-cmd --permanent --add-port=1985/tcp && firewall-cmd --reload
  ```

  Without it, a client moved to `xymons://` reports nothing and its columns go
  purple. SELinux needs nothing for 1985: [selinux.md](selinux.md) says why.

- **Config files.** Alerts in `alerts.cfg`, thresholds in `analysis.cfg`,
  graphs in `graphs.cfg` / `rrddefinitions.cfg`; each has a `.d/` directory for
  drop-ins.
- **Server identity.** `xymonserver.cfg`. On first install, `%post` rewrites
  `XYMONSERVERHOSTNAME` and `XYMONSERVERWWWNAME` to the real hostname, and
  renames the `localhost` entry in `hosts.cfg` to it. Change them if you
  rename the host.
- **Its own monitoring.** The `[xymonclient]` stanza in `tasks.cfg` runs the
  embedded client against `/etc/xymon-client/xymonclient.cfg`. That is why a
  server's `XYMSRV` stays `127.0.0.1`. Do not "fix" it.

## Changing a host's role

```sh
dnf swap xymon-client xymon     # promote a client to the server
dnf swap xymon xymon-client     # demote a server to a client
systemctl restart xymonlaunch
```

The swap stops the old role cleanly and keeps the unit enabled; the restart
brings the new one up. **After a demotion, set `XYMSRV`**: the former
server's config still says `127.0.0.1`.

## Migrating from the old layout

Before this design, `xymon` required `xymon-client` and a separate
`xymon-client.service` carried a `Conflicts=` guard.

- **Client-only hosts** upgrade normally: the client package's `%post`
  carries enablement and any running instance over to
  `xymonlaunch.service`.
- **Server hosts** have both packages. The new `xymon` obsoletes the old
  `xymon-client` (every old-layout build is `4.3.31-0.<date>`), so
  `dnf upgrade` replaces the pair with the server alone; the running
  server and the configuration carry over.

## When something is wrong

| Symptom | Look here |
| --- | --- |
| Host missing from the web UI | in `hosts.cfg`? `MACHINEDOTS` matching? unit running? |
| Host shows as a "ghost" | reported name differs from `hosts.cfg` |
| Host green but no cpu/disk/memory | not matched in `hosts.cfg` — check for a duplicate address |
| Client runs, no data arrives | `XYMSRV`; port 1984 reachable (firewalld service `bb` on the server); `xymonclient.log` |
| Sections empty (ifstat, ports, route) | `net-tools` missing, or the collector failed: `xymonclient.log` |
| Web UI loads on the server but not from elsewhere | firewalld service `http` (or `https`) on the server |
| Web pages 500 | `xymonpasswd` missing or not `apache`-owned; httpd error log |
| Nothing running after a swap | `systemctl restart xymonlaunch` |

## Package versions: snapshots, previews and releases

Three kinds of package come from the same spec:

| Kind | Built from | Channel |
| --- | --- | --- |
| **Release** | a `rel-*` tag; 4.3.31 is the first | stable, enabled by the repo file |
| **Snapshot** | upstream `main`, nightly when it or the packaging has moved | `xymon-snapshot`, off by default |
| **Preview** | xymon-experimental: `main` plus the pull requests of a milestone and those before it, mostly unreviewed | `xymon-preview-next` (the next release) or `xymon-preview` (every unreleased milestone), off by default |

Enable one preview channel, not together with the snapshot channel; the
README's *Previews* has the commands. A snapshot or preview sorts below the
eventual release, so a snapshot host is absorbed into the stable channel
cleanly when the release lands. How the version strings are built, and why,
is in the README's *Versioning*.

How this packaging compares with Debian's, Terabithia's and FreeBSD's:
[deployment-strategies.md](deployment-strategies.md).
