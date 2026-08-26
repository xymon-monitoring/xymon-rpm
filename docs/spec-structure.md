# How the spec is laid out

`rpm/xymon.spec` is one spec, ~740 lines, that builds five packages from the
upstream tree with no patches. It reads long because it compensates in
`%install` and the scriptlets for things upstream does not yet provide (see
[upstream.md](upstream.md) for which upstream PRs would let each go away).
This is a map of where to look, not a re-explanation of the packaging — the
spec is heavily commented inline, so this says *where*, the comments say *why*.

## Landmarks

| Where | What |
| --- | --- |
| **header** (top) | build knobs `--with selinux` (off by default) and `--without xymonping`; the globals that matter most: `xymonhome` (`/usr/lib/xymon`), and `dropindir`/`server.conf`/`client.conf` — the systemd drop-ins that pick a host's role |
| **`%create_xymon_account`** | the `xymon` system user/group, via `sysusers.d` with a `sysusers_create_compat` fallback for RPM too old to have the macro |
| **`%package` blocks** | `xymon`, `client`, `client-local`, `devel`, `tools`, each with its `%description`. `xymon` and `xymon-client` `Conflict` — one host is a server or a client |
| **`%build`** | configures and builds upstream. Carries Xymon's own `-g -O2` (the missing-hardening note and [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163) live here); compiles the SELinux `.pp` per `targeted/mls/minimum` only under `--with selinux` |
| **`%install`** | the compensation layer. Moves the httpd config where a web server reads it (`#412`), splits static web content off the writable tree (`#414`), installs the systemd unit + role drop-ins (`#415`), the sysusers file, and the SELinux modules. Each workaround names its upstream PR |
| **scriptlets** | `%pretrans` (lua, the layout migration), `%pre` (account), **`%post`** (systemd preset, tmpfiles, the `localhost`→`uname -n` rewrite, `semanage` file labeling, `semodule` load), `%preun`/`%postun` — and the parallel `client` set |
| **`%files`** | one block per package; the client tree is shipped identically by both `xymon` and `xymon-client` |

## See also

- [upstream.md](upstream.md) — where `rpm/sources/` files come from, and the
  upstream PRs that would shrink `%install`
- [selinux.md](selinux.md) — the `%build`/`%post` SELinux path in detail
- README *Versioning* — how `Version`/`Release` are computed at build time
