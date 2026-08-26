# The SELinux policy

The packaging carries two SELinux type-enforcement modules, `xymon.te` and
`xymon-client.te` (in `rpm/sources/`), adapted from the Terabithia lineage.
They exist because Xymon's runtime layout under `/usr/lib/xymon` conflicts
with the default targeted policy in a few specific places.

## Two independent parts

- **File-context labels** are applied in `%post` whenever `semanage` is
  present, *regardless of how the package was built*. They label the CGIs
  `httpd_sys_script_exec_t`, the `www` tree and `/usr/share/xymon`
  `httpd_sys_content_t`, and `rep`/`snap` `httpd_sys_rw_content_t`, then
  `restorecon`. Without these the CGIs are `lib_t` and the web tree
  `var_lib_t`, both denied to `httpd_t`.
- **The type-enforcement modules** are **off by default** (`%bcond_with
  selinux`). By default the `.te` files ship as `%doc` reference and are not
  compiled. Only a `--with selinux` build compiles them.

## What the modules grant

The rules address denials seen on an enforcing host:

- **`httpd_sys_script_t` → `httpd_cache_t`** (create/write/unlink/rename): the
  on-demand `report.cgi`/`snapshot.cgi` regenerating content under
  `/var/cache/xymon`.
- **CGI → `sendto`/`connectto` on the daemon domains**: `showgraph` flushing
  the RRD control sockets (and `rrdcached` if used).
- **`httpd_sys_script_t` → `var_log_t` read**: the ack/notification CGIs.
- **`ping_t`**: fping's temp files.

## Building and loading the modules

```sh
rpmbuild -ba rpm/xymon.spec --define 'baseversion 4.3.31' --with selinux
```

`%build` compiles each of `targeted mls minimum` via
`/usr/share/selinux/devel/Makefile`; `%install` ships the `.pp` under
`%{_datadir}/selinux/<variant>/`; and `%post` loads the matching one with
`semodule -s <variant> -i …` (best-effort — a container or permissive host
just skips it). The CI `selinux` target builds this on `almalinux:10`, so a
green run proves only that the policy **compiles** — nothing in CI runs
enforcing.

## Validating on an enforcing host — help wanted

This is the one part CI cannot exercise. To test it end to end on a real
enforcing RHEL/Oracle box:

```sh
setenforce 1                       # confirm: getenforce -> Enforcing
dnf install ./xymon-*.rpm          # a --with selinux build
# exercise the web UI: open a host page, a graph (showgraph), an
# acknowledgement, and an on-demand report/snapshot
ausearch -m avc -ts recent         # any AVC denial is a policy gap
```

Report AVCs — and which action triggered them — as an issue on
`xymon-monitoring/xymon-rpm`.

## Known issue

The module rules still reference `/var/cache/xymon`, a path this layout does
not use (the `rep`/`snap` labeling in `%post` targets the `www` tree instead).
Those dead rules should be reconciled with the actual `%post` labeling.
