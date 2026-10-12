# The SELinux policy

Xymon's runtime layout under `/usr/lib/xymon` and `/var/lib/xymon` has no
file contexts in the default targeted policy, so on an enforcing host
everything there is `lib_t` or `var_lib_t` — and both the daemons and the
CGIs are denied. The packaging fixes that in two parts: file and port labels
applied in `%posttrans`, and two type-enforcement modules, `xymon.te` and
`xymon-client.te` (in `rpm/sources/`), adapted from the Terabithia lineage.
Why each label is what it is sits beside it in the spec's `%posttrans`; this page
is what an administrator sees.

## What `%posttrans` labels

Applied whenever `semanage` is installed — a weak dependency of both the
server and the client package, so a default `dnf install` brings it; an
`rpm -i`, or `dnf` with weak dependencies off, does not, and then nothing is
labeled.

| path or port | label | without it |
| --- | --- | --- |
| `/usr/lib/xymon/server/bin`, `client/bin` | `bin_t` | the daemons run in `init_t`, and cannot reach xymond, the client's temp files or the network tests' ports |
| `server/bin/cgiwrap` | `httpd_sys_script_exec_t` | every CGI is a hard link to it, so `bin_t` would turn them all, and they would run as `httpd_t` |
| `cgi-bin`, `cgi-secure` | `httpd_sys_script_exec_t` | httpd will not run the CGIs |
| `/var/lib/xymon/www`, `/usr/share/xymon` | `httpd_sys_content_t` | httpd will not serve the pages |
| `www/rep`, `www/snap` | `httpd_sys_rw_content_t` | on-demand reports and snapshots cannot be written |
| `/var/lib/xymon/rrd` | `httpd_sys_content_t` | graphs cannot read their data |
| `/var/lib/xymon/tmp` | `httpd_sys_rw_content_t` | graphs cannot flush pending updates |
| TCP port 1984 | `xymon_port_t` | the CGIs cannot query xymond |

The client package labels `client/bin` itself. Erasing either package removes
its rules, except `client/bin`'s while the other package is installed.

## The modules

Built and loaded by default; a `--without selinux` build leaves them out, and
then port 1984 stays unlabeled and the CGIs cannot reach xymond.

- **`xymon_port_t`**, which `%posttrans` gives to 1984, and the one rule that lets
  the CGIs (`httpd_sys_script_t`) connect to it. The alternative, the
  `httpd_can_network_connect` boolean, lets every httpd script on the host
  connect to any port.
- **CGI → `sendto` on the daemon domains**: `showgraph` flushing the RRD
  control sockets.
- **`httpd_sys_script_t` → `var_log_t` read**: the ack/notification CGIs.
- **`ping_t`**: fping's temp files.

`%post` loads the `targeted` and `minimum` modules the host has, best-effort:
a container, or a host with SELinux disabled, just skips it.

**Xymon does not run on an `mls` host**, and no `mls` module is built. The
module requires `unconfined_service_t` and the `initrc_*` types, which only
`targeted` and `minimum` define, so `semodule` refuses it there; and without
`unconfined_service_t` the daemons stay in `init_t` whatever their label.
Supporting `mls` would need a policy with domains of its own for the
daemons.

## Validating on an enforcing host

Validated enforcing with the `targeted` policy on AlmaLinux 8, 9 and 10 and
Fedora 44 — fresh server installs, a client-only host, and on AlmaLinux 9 an
upgrade from a package without these labels and both role swaps — and with
Fedora's `minimum` policy; the pull request that added them has the record.
CI compiles the modules on every target but runs nothing enforcing, so RHEL
itself, and any release not listed, is still worth a report:

```sh
getenforce                         # Enforcing
dnf install xymon httpd
systemctl enable --now httpd xymonlaunch
ps -eZ | grep -E ' (xymond|xymonlaunch)$'   # unconfined_service_t, not init_t
# open a host page, a graph, an acknowledgement, a report and a snapshot
ausearch -m avc -ts recent         # any AVC is a policy gap
```

`ausearch` reads standard input instead of the logs when it is not run from a
terminal — from a script, or `ssh host cmd` — and then finds nothing; add
`--input-logs` there.

Report AVCs — and which action triggered them — as an issue on
`xymon-monitoring/xymon-rpm`.

## Known issue

The module rules still reference `/var/cache/xymon`, a path this layout does
not use (`rep` and `snap` are labeled under the `www` tree instead). Those
dead rules should be reconciled with the actual `%posttrans` labeling.
