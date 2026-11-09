# How the spec is laid out

`rpm/xymon.spec` is one spec, about 940 lines, that builds five packages from the
upstream tree with no patches. It reads long because `%install` and the
scriptlets compensate for what upstream does not yet provide
([upstream.md](upstream.md) names the upstream PRs that would retire each).
The spec's inline comments say *why*; this map says *where*.

## Landmarks

| Where | What |
| --- | --- |
| **header** (top) | build knobs `--without selinux` (policy modules, on by default) and `--with xymonping` (setuid helper, off by default: fping is used); the globals `xymonhome` (`/usr/lib/xymon`) and `dropindir`/`serverconf`/`clientconf`, the systemd drop-ins that pick a host's role |
| **`%create_xymon_account`** | the `xymon` user and group, expanded into both packages' `%pre`: `%sysusers_create_compat` from `xymon.sysusers`, or `groupadd`/`useradd` on EL8, whose rpm predates the sysusers macros |
| **`%package` blocks** | `xymon`, `client`, `client-local`, `devel`, `tools`, each with its `%description`. `xymon` `Conflicts:` `xymon-client` (a host is server or client) and obsoletes the old layout's `xymon-client < 4.3.31-1` |
| **`%build`** | configures and builds upstream, passing `%{optflags}` and `%{build_ldflags}` through the environment (the comment says why not the make command line); compiles the SELinux `.pp` per `targeted`/`minimum` unless `--without selinux` |
| **`%install`** | the compensation layer, each workaround's comment naming its upstream PR: the httpd config moved where httpd reads it (`#412`), static web content split off the writable tree (`#414`), client config moved to `/etc/xymon-client` with its drop-in directories (`#411`), a hand-written `xymon.pc` (`#410`). Also the systemd unit and role drop-ins (`#415`, cited in upstream.md, not the spec), the sysusers file and the SELinux modules |
| **scriptlets** | `%pretrans` (lua, the layout migration), `%pre` (account), **`%post`** (systemd preset, tmpfiles, the `localhost`→`uname -n` rewrite, `semodule` load), **`%posttrans`** (`semanage` file and port labeling, the httpd reload), `%preun`/`%postun`, and the parallel `client` set |
| **`%files`** | one block per package; `%client_tree_filelist` ships the client tree in both `xymon` and `xymon-client`, except `clientlaunch.d`, which only the client package owns |

## See also

- [upstream.md](upstream.md) — where `rpm/sources/` files come from, and the
  upstream PRs that would shrink `%install`
- [selinux.md](selinux.md) — the `%build`/`%post`/`%posttrans` SELinux path in detail
- README *Versioning* — how `Version`/`Release` are computed at build time
