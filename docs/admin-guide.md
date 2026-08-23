# Where things live, and how to run them

A host is either a **server** (`xymon`) or a **client** (`xymon-client`);
the packages conflict, so nothing is ever both. Both run the same service,
`xymonlaunch.service`, so every command below is identical everywhere —
only the files differ. A server also monitors *itself* through an embedded
client tree driven from its own `tasks.cfg`, so finding client files on a
server is normal.

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
└── www/                        what xymongen writes, + symlinks to the static content
/var/log/xymon/                 xymonlaunch.log xymond.log xymonclient.log …
/usr/bin/xymon  /usr/bin/xymoncmd  /usr/sbin/xymonlaunch   for typing by hand
```

A **client host** (`xymon-client`) has only the client half:

```
/etc/xymon-client/              xymonclient.cfg (XYMSRV), clientlaunch.cfg, localclient.cfg
/etc/sysconfig/xymon-client     MACHINEDOTS, SERVEROSTYPE
/etc/logrotate.d/xymon          (both roles ship this)
/usr/lib/xymon/client/bin/      xymonclient.sh, logfetch, clientupdate, xymonlaunch …
/usr/lib/xymon/client/ext/  local/   your own extension scripts
/var/log/xymon/                 clientlaunch.log …
```

The service and its role drop-in, on both:

```
/usr/lib/systemd/system/xymonlaunch.service
/usr/lib/systemd/system/xymonlaunch.service.d/{server,client}.conf
```

Nothing writes inside `/usr/lib`: symlinks redirect everything mutable into
`/etc`, `/var` and `/tmp`. `/run/xymon` is created by tmpfiles but unused —
see the README's known gaps.

## Running the service

```sh
systemctl status xymonlaunch
systemctl start|stop|restart xymonlaunch
journalctl -u xymonlaunch -f
```

The real logs are files under `/var/log/xymon/`, not the journal: start with
`xymonlaunch.log`, `xymond.log`, `xymonclient.log` on a server;
`clientlaunch.log` on a client.

`systemctl reload` sends `SIGHUP`, which `xymonlaunch` acts on (rereads
`tasks.cfg`, reopens its log) but does not pass to the daemons it started —
so use `restart` to reach those until upstream
[xymon#172](https://github.com/xymon-monitoring/xymon/pull/172) merges.

To tell which role is running (only the client names `clientlaunch.cfg`):

```sh
systemctl show -p MainPID --value xymonlaunch | xargs -I{} tr '\0' ' ' < /proc/{}/cmdline
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
  stanza in `clientlaunch.cfg`.
- **Analyse locally.** Install `xymon-client-local`, put rules in
  `localclient.cfg`, add `--local` to the client's entry in `clientlaunch.cfg`.

## Server tasks

- **Add a host.** Edit `/etc/xymon/hosts.cfg` (or a file in `hosts.d/`), then
  restart. The name must match what the client reports, and **the address must
  be unique** — Xymon keys hosts by address, so a second entry for an
  address already listed is ignored (rename the existing entry instead). An
  unmatched host still shows green from network tests while its client data is
  never analysed.
- **Web access.** The UI is `http://<server>/xymon/`. The authenticated CGIs
  read `/etc/xymon/xymonpasswd`, which ships empty and `apache`-owned, so add a
  user before anyone can log in:

  ```sh
  htpasswd /etc/xymon/xymonpasswd alice     # -c only for the first user
  ```

- **Config files.** Alerts in `alerts.cfg`, thresholds in `analysis.cfg`,
  graphs in `graphs.cfg` / `rrddefinitions.cfg`; each has a `.d/` directory for
  drop-ins.
- **Server identity.** `xymonserver.cfg`. `%post` rewrites
  `XYMONSERVERHOSTNAME` to the real hostname on first install; change it there
  if you rename the host.
- **Its own monitoring.** The `[xymonclient]` stanza in `tasks.cfg` runs the
  embedded client against `/etc/xymon-client/xymonclient.cfg`. That is why a
  server's `XYMSRV` stays `127.0.0.1` — do not "fix" it.

## Changing a host's role

```sh
dnf swap xymon-client xymon     # promote a client to the server
dnf swap xymon xymon-client     # demote a server to a client
systemctl restart xymonlaunch
```

The swap stops the old role cleanly and keeps the unit enabled; the restart
brings the new one up. **After a demotion, set `XYMSRV`** — the former
server's config still says `127.0.0.1`.

## When something is wrong

| Symptom | Look here |
| --- | --- |
| Host missing from the web UI | in `hosts.cfg`? `MACHINEDOTS` matching? unit running? |
| Host shows as a "ghost" | reported name differs from `hosts.cfg` |
| Host green but no cpu/disk/memory | not matched in `hosts.cfg` — check for a duplicate address |
| Client runs, no data arrives | `XYMSRV`; port 1984 reachable; `clientlaunch.log` |
| Sections empty (disk, ports, ifstat) | `net-tools` missing, or the collector failed — `clientlaunch.log` |
| Web pages 500 | `xymonpasswd` missing or not `apache`-owned; httpd error log |
| Nothing running after a swap | `systemctl restart xymonlaunch` |
| `dnf upgrade` fails on a server | pre-conflict layout: `dnf swap xymon-client xymon` |

How this packaging compares with Debian's, Terabithia's and FreeBSD's:
[deployment-strategies.md](deployment-strategies.md).
