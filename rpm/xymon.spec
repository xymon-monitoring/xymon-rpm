#
# Xymon RPM package
#
# Built from the xymon-monitoring/xymon source tree, not from a patched
# fork: this spec carries no source patches at all. Fixes belong upstream.
#
# Versioning (see README.md)
#   release   rpmbuild --define 'baseversion 4.3.31'
#             -> xymon-4.3.31-1.el10.x86_64.rpm
#   snapshot  rpmbuild --define 'baseversion 4.3.31' \
#                      --define 'gitsnapshot 0.20260730git3a07523.202607301210pab12cd3'
#             -> xymon-4.3.31-0.20260730git3a07523.202607301210pab12cd3.el10.x86_64.rpm
#
# The snapshot string names the upstream commit and then the packaging
# commit; CI computes it (see build.yml). Only its leading 0. matters to
# this spec.
#
# The leading 0. in a snapshot release sorts below the eventual -1, so a
# snapshot user is absorbed into the stable channel when the release lands.
#
%{!?baseversion: %global baseversion 4.3.31}
# releasenum exists for packaging-only re-releases of a tagged version:
# a published NEVRA is immutable, so a fix to an already-released X.Y.Z
# must ship as -2 rather than rebuild -1.
%{!?releasenum: %global releasenum 1}
%{?gitsnapshot: %global xymonrelease %{gitsnapshot}}
%{!?gitsnapshot: %global xymonrelease %{releasenum}}

# xymonping is a setuid-root ICMP helper. Upstream's own CI builds it, so
# it is on by default; --without xymonping falls back to fping at runtime.
%bcond_without xymonping

# The SELinux policy modules. Off by default: the policy compiles and is
# shipped compiled by the Terabithia packages, but nothing in CI runs
# enforcing SELinux, so a green build proves only that it compiles, not
# that it is correct. Enable with --with selinux once someone has verified
# it on an enforcing machine.
#
# The modules declare no new types -- they `require` existing ones and add
# allow rules -- so there is no .fc and nothing to label.
%bcond_with selinux
%global selinux_variants targeted mls minimum

%global xymonhome  %{_prefix}/lib/xymon

# The per-role drop-ins. Named once: %%install, %%files and the %%preun
# swap guards all derive their paths from these, so a rename cannot turn
# a guard silently always-true.
%global dropindir  %{_unitdir}/xymonlaunch.service.d
%global serverconf %{dropindir}/server.conf
%global clientconf %{dropindir}/client.conf

Name:           xymon
Version:        %{baseversion}
Release:        %{xymonrelease}%{?dist}
Summary:        Xymon network and systems monitor
License:        GPL-2.0-only
URL:            https://github.com/xymon-monitoring/xymon
Source0:        xymon-%{version}.tar.gz

# Runtime integration files. Provenance is deliberate -- see README.md.
#   written here (started from Terabithia's xymon-4.3.30 unit): ONE unit
#   for both roles, shipped identically by the server and the client
#   package. xymonlaunch-run picks the role: the server tree when it is
#   installed, otherwise the client tree in the foreground (upstream's
#   runclient.sh starts xymonlaunch without --no-daemon, so it forks
#   and the script exits, leaving a Type=simple unit nothing to
#   supervise):
Source1:        xymonlaunch.service
Source3:        xymonlaunch-run
#   per-role drop-ins for the shared unit: the buildroot can hold only
#   one file per path, so what differs between the roles ships as a
#   drop-in owned by the role's package:
Source14:       xymonlaunch-server.conf
Source15:       xymonlaunch-client.conf
#   byte-identical in Terabithia and upstream devel:
Source4:        xymonlaunch.service.preset
Source5:        xymon-tmpfiles.conf
#   adapted here: devel's postrotate signals xymonlaunch, which main
#   cannot act on until xymon#172; and devel's xymon-client.default
#   documents XYMONSERVERS, which only patched clients read -- see
#   README.md:
Source6:        xymon.logrotate
Source8:        xymon-client.default
#   from upstream devel via PR #46:
Source7:        xymonlaunch.default
Source9:        xymon.te
Source10:       xymon-client.te
Source11:       xymon-sysctl.conf
Source12:       bb.xml
#   written here: Fedora's rpm generates Requires: user(xymon)/group(xymon)
#   for any package owning files with a non-root owner, and only a
#   sysusers.d snippet generates the matching Provides.
Source13:       xymon.sysusers

# The client tree, shipped by BOTH packages (they conflict, so no host
# ever installs it twice). Defined once and expanded into both %%files
# sections so they cannot drift: an entry added here gets identical
# config/attr handling in either role.
%global client_tree_filelist %{expand:
%{xymonhome}/client
%dir %{_sysconfdir}/xymon-client
%config(noreplace) %{_sysconfdir}/xymon-client/xymonclient.cfg
%config(noreplace) %{_sysconfdir}/xymon-client/clientlaunch.cfg
%config(noreplace) %{_sysconfdir}/xymon-client/localclient.cfg
%attr(0750,root,xymon) %{xymonhome}/client/bin/logfetch
%attr(0750,root,xymon) %{xymonhome}/client/bin/clientupdate
%config(noreplace) %{_sysconfdir}/logrotate.d/xymon
%{?_sysusersdir:%{_sysusersdir}/xymon.conf}
}

# Layout moves have to be prepared before anything is unpacked, because
# rpm will not replace a directory with a symlink -- the transaction
# fails on the existing directory instead. That is what %%pretrans is
# for. Two moves need it: the client configuration, which went from
# %%{xymonhome}/client/etc to /etc/xymon-client, and the static web
# content, which went from the www tree to %%{_datadir}/xymon. Both
# leave a symlink where the directory used to be.
#
# Contents are carried over rather than discarded, so an admin's edited
# xymonclient.cfg or a custom gif dropped into www/gifs survives the
# move; anything the package itself ships is simply overwritten when the
# new files are unpacked a moment later.
%global migrate_tree %{expand:
-- mkdir -p: posix.mkdir makes one level only, and the new parents
-- (/usr/share/xymon) do not exist yet on a host still running the old
-- layout.
local function mkdirp(path)
  local acc = ""
  for part in string.gmatch(path, "[^/]+") do
    acc = acc .. "/" .. part
    posix.mkdir(acc)
  end
end

local function movetree(old, new)
  local st = posix.stat(old)
  if not (st and st.type == "directory") then return end
  mkdirp(new)
  for i, f in ipairs(posix.dir(old) or {}) do
    if f ~= "." and f ~= ".." then
      local src = old .. "/" .. f
      local dst = new .. "/" .. f
      local sst = posix.stat(src)
      if sst and sst.type == "directory" then
        movetree(src, dst)
      else
        -- Remove the source only once the copy is known to have
        -- landed: deleting on a failed write would destroy whatever
        -- the admin put there.
        local moved = posix.stat(dst) ~= nil
        if not moved then
          local fin = io.open(src, "rb")
          if fin then
            local data = fin:read("*a")
            fin:close()
            local fout = io.open(dst, "wb")
            if fout then
              fout:write(data)
              fout:close()
              moved = posix.stat(dst) ~= nil
            end
          end
        end
        if moved then os.remove(src) end
      end
    end
  end
  -- The path has to be free for the symlink either way. If anything
  -- could not be moved, keep it under .rpmorig rather than delete it.
  if not posix.rmdir(old) then
    os.rename(old, old .. ".rpmorig")
  end
end
}

# Account creation, expanded into both packages' %%pre: with no
# dependency between the packages, whichever installs first must create
# the xymon user itself. One definition so the two scriptlets cannot
# drift. (EL8 predates the sysusers rpm macros, hence the fallback.)
%global create_xymon_account %{expand:%{?sysusers_create_compat:%sysusers_create_compat %{SOURCE13}}%{!?sysusers_create_compat:
getent group xymon >/dev/null || groupadd -r xymon
getent passwd xymon >/dev/null || useradd -r -g xymon -d %{xymonhome} -s /sbin/nologin -c "Xymon monitor" xymon}
exit 0}

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  c-ares-devel
BuildRequires:  openldap-devel
BuildRequires:  openssl-devel
BuildRequires:  pcre2-devel
BuildRequires:  rrdtool-devel
BuildRequires:  libtirpc-devel
BuildRequires:  zlib-devel
BuildRequires:  systemd-rpm-macros
%{?systemd_requires}
%if %{with selinux}
BuildRequires:  checkpolicy
BuildRequires:  selinux-policy-devel
Requires(post):   policycoreutils
Requires(postun): policycoreutils
%endif

Requires(pre):  shadow-utils
%{?sysusers_requires_compat}
# A host is either a server or a client, never both. The --server build
# always produces the client tree too (the server monitors itself
# through it), so this package ships that tree itself rather than
# depending on xymon-client -- and the standalone client package becomes
# mutually exclusive with it. Role changes are one dnf swap; the
# runnable recipe lives in README.md only.
Conflicts:      xymon-client
# The embedded client's collectors shell out to these, same as the
# standalone client's (see the client package's net-tools comment).
Requires:       net-tools
# This package ships /etc/logrotate.d/xymon; nothing rotates it otherwise.
Recommends:     logrotate
# Owns the apache group that www/rep and www/snap are chgrp'd to, and the
# /etc/httpd/conf.d directory the web config drops into. rpm >= 4.19
# generates a group(apache) requirement from the %%attr on its own, but
# EL8/EL9 rpm does not, and there the dirs would silently fall back to
# root's group.
Requires:       httpd-filesystem
%if %{without xymonping}
# Without the setuid xymonping helper, xymonnet shells out to fping.
Requires:       fping
%endif
# semanage, for the file-context labeling in %%post. Weak on purpose: a
# container or a disabled-SELinux host works without it.
Recommends:     policycoreutils-python-utils

%description
Xymon is a system for monitoring servers, networks and applications. It
polls network services, collects data reported by clients, raises alerts,
and renders the results as a web front-end backed by RRD graphs.

This package contains the server, including the client component the
server runs on itself; it conflicts with xymon-client, which is the
same client packaged alone for every other host.

%package client
Summary:        Client for the Xymon network monitor
Requires(pre):  shadow-utils
# Both packages own the account definition: with the dependency between
# them gone, each must be able to create the xymon user on its own.
%{?sysusers_requires_compat}
%{?systemd_requires}
# xymonclient-linux.sh hardcodes ifconfig, netstat and route with no
# ip/ss fallback; without them the ifstat/ports/route sections silently
# arrive empty.
Requires:       net-tools
# The client ships /etc/logrotate.d/xymon; nothing rotates it otherwise.
Recommends:     logrotate

%description client
Client-side data collection for Xymon. It gathers CPU, memory, filesystem,
process and log data from the local system and reports it to a Xymon
server, which evaluates the data against its configured thresholds.

Install it on hosts that are not the Xymon server. The server package
embeds this same client and conflicts with this package: a host is one
role or the other, and both run it as xymonlaunch.service.

%package client-local
Summary:        Local threshold analysis for the Xymon client
# Either role satisfies this: the server ships xymond_client itself and
# the standalone client needs this package to get it.
Requires:       (xymon = %{version}-%{release} or xymon-client = %{version}-%{release})

%description client-local
Installs xymond_client on a client machine, so thresholds can be evaluated
locally instead of on the server. Configure it through localclient.cfg,
which the xymon-client package installs, and add --local to the client's
entry in clientlaunch.cfg.

The binary is the same one the server uses, and is deliberately shared
with the xymon package rather than moved out of it: a Xymon server needs
xymond_client for its own analysis, so removing it there to place it here
would break every server that did not also install this package.

%package devel
Summary:        Headers and static libraries for building Xymon modules
# A -devel package has to bring what its own headers include, or it
# builds only where Xymon's build dependencies already happen to be --
# which is a build host, not the machine of someone writing a module.
# libxymon.h reaches pcre2.h through lib/loadalerts.h; rrd.h is reached
# only by lib/rrd_api_compat.h, so that one is weak: a module that does
# not touch the RRD API does not need it.
Requires:       pcre2-devel
Recommends:     rrdtool-devel

%description devel
Headers and static libraries for building worker modules and other
components against Xymon.

Xymon's build installs neither, so they are collected here from the build
tree. `include/` and `lib/` are kept as siblings under a single directory
because libxymon.h reaches its remaining headers by relative path
("../lib/..."), so flattening them would break every include. Build
against it with:

    cc -I%{_includedir}/xymon/include ... -L%{_libdir}/xymon -lxymon

%package tools
Summary:        Diagnostic tools for the Xymon server

%description tools
Small standalone programs for inspecting Xymon's configuration parsing and
internal structures: stackio, locator, tree, availability and loadhosts.

They are built by Xymon's own makefiles but never installed, since lib/ has
no install rule. Most administrators will not need them.

%prep
%setup -q

%build
# The distribution's hardening flags are deliberately NOT injected here.
# On main there is no working way to do it:
#
#   - on the make command line, a CFLAGS= assignment overrides makefile `+=`
#     and drops lib/Makefile's own -I../include, so the build cannot find
#     its headers;
#   - via the environment, build/Makefile.Linux assigns CFLAGS with a plain
#     `=` and discards it -- while LDFLAGS *does* survive, so exporting both
#     compiles without -fPIC but links with -pie and fails on the resulting
#     R_X86_64_32 relocation.
#
# xymon-monitoring/xymon#163 changes Makefile.Linux to `?=` plus `+=`, which
# makes the environment route work. Until it merges, the package is built
# with Xymon's own -g -O2 and carries no FORTIFY/stack-protector/PIE.
# Restoring the flags afterwards is two `export` lines here.
#
# One consequence has to be handled: Fedora and EL10 ship gcc with
# --enable-default-pie, so the link defaults to -pie while Xymon's flags
# compile without -fPIC, and the link dies on an R_X86_64_32 relocation.
# EL8/EL9 gcc does not default that way, which is why only the newer
# targets hit it. LDFLAGS is the one variable the build does take from the
# environment, so turn the default back off there. This line goes away with
# #163, which lets the matching -fPIE reach the compiler instead.
export LDFLAGS="-no-pie"

# XYMONHOSTNAME is deliberately baked as "localhost": the value would
# otherwise be the build host's name, which is meaningless to every
# consumer of the package. %%post rewrites it to the real hostname on
# first install. This mirrors what Terabithia's spec does, and is the
# packaging-side answer to the build-time-hostname problem (TBT 40).
USEXYMONPING=%{?with_xymonping:y}%{!?with_xymonping:n} \
ENABLESSL=y \
ENABLELDAP=y \
ENABLELDAPSSL=y \
XYMONUSER=xymon \
XYMONTOPDIR=%{xymonhome} \
XYMONVAR=%{_sharedstatedir}/xymon \
XYMONLOGDIR=%{_localstatedir}/log/xymon \
XYMONHOSTNAME=localhost \
XYMONHOSTIP=127.0.0.1 \
XYMONHOSTURL=/xymon \
XYMONCGIURL=/xymon-cgi \
SECUREXYMONCGIURL=/xymon-seccgi \
CGIDIR=%{xymonhome}/cgi-bin \
SECURECGIDIR=%{xymonhome}/cgi-secure \
HTTPDGID=apache \
MANROOT=%{_mandir} \
INSTALLBINDIR=%{xymonhome}/server/bin \
INSTALLETCDIR=%{_sysconfdir}/xymon \
INSTALLWEBDIR=%{_sysconfdir}/xymon/web \
INSTALLEXTDIR=%{xymonhome}/server/ext \
INSTALLTMPDIR=%{_sharedstatedir}/xymon/tmp \
INSTALLWWWDIR=%{_sharedstatedir}/xymon/www \
./configure --server

%make_build PKGBUILD=1

%if %{with selinux}
# Built in a subdirectory so the sed below does not touch the copies
# shipped as documentation. `VERSION` is a literal placeholder in both
# files and has to be substituted before checkmodule will accept them.
mkdir -p selinux-build
cp -p %{SOURCE9} %{SOURCE10} selinux-build/
sed -i 's/\bVERSION\b/%{version}/' selinux-build/*.te
for v in %{selinux_variants}; do
    make -C selinux-build -f /usr/share/selinux/devel/Makefile NAME="$v"
    mv selinux-build/xymon.pp        "selinux-build/xymon.pp.$v"
    mv selinux-build/xymon-client.pp "selinux-build/xymon-client.pp.$v"
    make -C selinux-build -f /usr/share/selinux/devel/Makefile NAME="$v" clean
done
%endif

%install
%make_install INSTALLROOT=%{buildroot} PKGBUILD=1

%if %{with selinux}
for v in %{selinux_variants}; do
    install -Dpm 0644 "selinux-build/xymon.pp.$v" \
        %{buildroot}%{_datadir}/selinux/"$v"/xymon.pp
    install -Dpm 0644 "selinux-build/xymon-client.pp.$v" \
        %{buildroot}%{_datadir}/selinux/"$v"/xymon-client.pp
done
%endif

# systemd: ONE unit for both roles, shipped by both packages (they
# conflict, so it is never on a host twice). xymonlaunch-run picks the
# role by which tree is installed.
install -Dpm 0644 %{SOURCE1}  %{buildroot}%{_unitdir}/xymonlaunch.service
install -Dpm 0755 %{SOURCE3}  %{buildroot}%{xymonhome}/client/bin/xymonlaunch-run
install -Dpm 0644 %{SOURCE14} %{buildroot}%{serverconf}
install -Dpm 0644 %{SOURCE15} %{buildroot}%{clientconf}
install -Dpm 0644 %{SOURCE4}  %{buildroot}%{_presetdir}/50-xymonlaunch.preset
install -Dpm 0644 %{SOURCE5}  %{buildroot}%{_tmpfilesdir}/xymon.conf
install -Dpm 0644 %{SOURCE6}  %{buildroot}%{_sysconfdir}/logrotate.d/xymon
install -Dpm 0644 %{SOURCE7}  %{buildroot}%{_sysconfdir}/sysconfig/xymonlaunch
install -Dpm 0644 %{SOURCE8}  %{buildroot}%{_sysconfdir}/sysconfig/xymon-client
install -Dpm 0644 %{SOURCE11} %{buildroot}%{_sysctldir}/70-xymon.conf
%if %{defined _sysusersdir}
install -Dpm 0644 %{SOURCE13} %{buildroot}%{_sysusersdir}/xymon.conf
%endif

# Admin conveniences on $PATH, not used by the unit: xymonlaunch-run
# execs the server tree's binaries directly, so these are for people
# typing xymoncmd or xymon by hand.
install -d %{buildroot}%{_bindir} %{buildroot}%{_sbindir}
ln -sf %{xymonhome}/server/bin/xymon    %{buildroot}%{_bindir}/xymon
ln -sf %{xymonhome}/server/bin/xymoncmd %{buildroot}%{_bindir}/xymoncmd
ln -sf %{xymonhome}/server/bin/xymonlaunch %{buildroot}%{_sbindir}/xymonlaunch

# The web server config is generated by the build (xymond/Makefile:142)
# into the Xymon etc dir; move it where httpd actually reads it.
install -d %{buildroot}%{_sysconfdir}/httpd/conf.d
mv %{buildroot}%{_sysconfdir}/xymon/xymon-apache.conf \
   %{buildroot}%{_sysconfdir}/httpd/conf.d/xymon-apache.conf

# The www tree mixes two different kinds of thing. gifs, help and menu
# are static package content -- shipped files that never change on a
# running host -- and the FHS puts those in /usr/share. The rest is
# state: html, notes, rep, snap and wml ship empty and are written by
# the daemons, and xymongen writes the generated pages into www itself,
# so XYMONWWWDIR has to stay writable and stays where it is.
#
# The three static trees move and are symlinked back, which keeps every
# URL under /xymon/ and every on-disk path working unchanged -- nothing
# in xymonserver.cfg or the CGIs has to learn a second location, and no
# extra httpd configuration is needed: the generated config already sets
# FollowSymLinks on the www directory, which is what lets httpd cross
# into /usr/share (verified -- without it the same request is a 403).
install -d %{buildroot}%{_datadir}/xymon
for d in gifs help menu; do
    mv %{buildroot}%{_sharedstatedir}/xymon/www/$d %{buildroot}%{_datadir}/xymon/$d
    ln -sf %{_datadir}/xymon/$d %{buildroot}%{_sharedstatedir}/xymon/www/$d
done

# That config points AuthUserFile/AuthGroupFile at these; the build never
# creates them, and without the password file every /xymon-seccgi request
# is a 500. Shipped empty: no user can authenticate until the admin adds
# one with htpasswd.
touch %{buildroot}%{_sysconfdir}/xymon/xymonpasswd
touch %{buildroot}%{_sysconfdir}/xymon/xymongroups

# Shipped as reference material only, so %%doc them from the build dir --
# %%doc cannot take a %%{SOURCEn} path directly.
cp -p %{SOURCE9} %{SOURCE10} %{SOURCE12} .

# Development files. The build installs neither headers nor the static
# libraries, so take them from the build tree. include/ and lib/ must stay
# siblings: libxymon.h pulls in 64 further headers as "../lib/...", so a
# flat include directory would break on the first #include.
install -d %{buildroot}%{_includedir}/xymon/include \
           %{buildroot}%{_includedir}/xymon/lib \
           %{buildroot}%{_libdir}/xymon
install -pm 0644 include/*.h %{buildroot}%{_includedir}/xymon/include/
install -pm 0644 lib/*.h     %{buildroot}%{_includedir}/xymon/lib/
install -pm 0644 lib/*.a     %{buildroot}%{_libdir}/xymon/

# Diagnostic tools. lib/Makefile builds these in its `all` target but has
# no install rule at all, so they are otherwise discarded with the build
# tree.
for t in stackio locator tree availability loadhosts; do
    install -pm 0755 "lib/$t" %{buildroot}%{xymonhome}/server/bin/"$t"
done

# The client tree ships its own tmp/logs as real dirs; redirect them.
rm -rf %{buildroot}%{xymonhome}/client/tmp %{buildroot}%{xymonhome}/client/logs
ln -sf %{_tmppath}            %{buildroot}%{xymonhome}/client/tmp
ln -sf %{_localstatedir}/log/xymon %{buildroot}%{xymonhome}/client/logs

# Client configuration belongs in /etc: the FHS wants /usr shareable and
# read-only, and an admin edits xymonclient.cfg (XYMSRV) more than any
# other file on a client host. Upstream already does this for the server
# -- its build symlinks server/etc to INSTALLETCDIR -- but provides no
# equivalent hook for the client, so the same move is made here. Every
# reference to these files, in clientlaunch.cfg and in the server's
# tasks.cfg alike, is spelled $XYMONCLIENTHOME/etc/... and resolves
# through the symlink, so nothing else has to know.
install -d %{buildroot}%{_sysconfdir}/xymon-client
mv %{buildroot}%{xymonhome}/client/etc/* %{buildroot}%{_sysconfdir}/xymon-client/
rmdir %{buildroot}%{xymonhome}/client/etc
ln -sf %{_sysconfdir}/xymon-client %{buildroot}%{xymonhome}/client/etc

%pretrans -p <lua>
%migrate_tree
movetree("%{xymonhome}/client/etc", "%{_sysconfdir}/xymon-client")
movetree("%{_sharedstatedir}/xymon/www/gifs", "%{_datadir}/xymon/gifs")
movetree("%{_sharedstatedir}/xymon/www/help", "%{_datadir}/xymon/help")
movetree("%{_sharedstatedir}/xymon/www/menu", "%{_datadir}/xymon/menu")

%pretrans client -p <lua>
-- The client package ships no www tree, so it has only the one move.
%migrate_tree
movetree("%{xymonhome}/client/etc", "%{_sysconfdir}/xymon-client")

%pre
%create_xymon_account

%pre client
%create_xymon_account

%post
# Skipped during a promotion, for the reason given in %%post client: the
# departing package's state must not be overridden by a preset run.
if [ ! -e %{clientconf} ]; then
%systemd_post xymonlaunch.service
fi
%tmpfiles_create %{_tmpfilesdir}/xymon.conf
# Replace the placeholder baked in at build time (see %%build).
if [ $1 -eq 1 ]; then
    sed -i -e "s/^XYMONSERVERHOSTNAME=.*/XYMONSERVERHOSTNAME=\"$(uname -n)\"/" \
           -e "s/^XYMONSERVERWWWNAME=.*/XYMONSERVERWWWNAME=\"$(uname -n)\"/" \
        %{_sysconfdir}/xymon/xymonserver.cfg || :
fi
# Label the web-facing paths so httpd can reach them on an enforcing
# host: the default policy has no contexts for /usr/lib/xymon, so the
# CGIs are lib_t and the www tree var_lib_t, both denied to httpd_t.
# Best-effort by design -- semanage only exists where the SELinux tooling
# is installed, and a container or disabled-SELinux host needs none of
# this.
if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t httpd_sys_script_exec_t '%{xymonhome}/cgi-bin(/.*)?'    2>/dev/null || :
    semanage fcontext -a -t httpd_sys_script_exec_t '%{xymonhome}/cgi-secure(/.*)?' 2>/dev/null || :
    semanage fcontext -a -t httpd_sys_content_t '%{_sharedstatedir}/xymon/www(/.*)?' 2>/dev/null || :
    semanage fcontext -a -t httpd_sys_content_t '%{_datadir}/xymon(/.*)?' 2>/dev/null || :
    semanage fcontext -a -t httpd_sys_rw_content_t '%{_sharedstatedir}/xymon/www/rep(/.*)?'  2>/dev/null || :
    semanage fcontext -a -t httpd_sys_rw_content_t '%{_sharedstatedir}/xymon/www/snap(/.*)?' 2>/dev/null || :
    restorecon -R %{xymonhome}/cgi-bin %{xymonhome}/cgi-secure \
        %{_sharedstatedir}/xymon/www %{_datadir}/xymon 2>/dev/null || :
fi
%if %{with selinux}
# Never fatal: a container or a machine with SELinux disabled has no
# working semodule, and failing there would abort an otherwise fine
# installation.
for v in %{selinux_variants}; do
    semodule -s "$v" -i %{_datadir}/selinux/"$v"/xymon.pp >/dev/null 2>&1 || :
done
%endif

%preun
# Swap-aware: in a demotion (dnf swap xymon xymon-client) the standalone
# client is already installed when this runs -- installs precede erases
# in a transaction -- so the unit's enablement must survive. The other
# role's packaged drop-in is the marker: it lives under /usr/lib (admin
# drop-ins go to /etc/systemd), so unlike a config-file probe it cannot
# be faked by configuration, and unlike `rpm -q` it cannot deadlock the
# rpmdb from inside a scriptlet.
#
# The running server IS stopped here, while server.conf is still on disk
# and in effect: it is what keeps xymond's children alive through the
# stop so they can finish checkpoints and cache flushes. Stopping later
# -- after the erase takes that drop-in away -- would kill the whole
# cgroup mid-write. Enablement is untouched, so the swap's `systemctl
# restart` brings the new role up in its place.
if [ -e %{clientconf} ]; then
    systemctl stop xymonlaunch.service >/dev/null 2>&1 || :
else
%systemd_preun xymonlaunch.service
fi

%postun
%systemd_postun_with_restart xymonlaunch.service
if [ $1 -eq 0 ] && command -v semanage >/dev/null 2>&1; then
    semanage fcontext -d '%{xymonhome}/cgi-bin(/.*)?'    2>/dev/null || :
    semanage fcontext -d '%{xymonhome}/cgi-secure(/.*)?' 2>/dev/null || :
    semanage fcontext -d '%{_sharedstatedir}/xymon/www(/.*)?'      2>/dev/null || :
    semanage fcontext -d '%{_datadir}/xymon(/.*)?'                 2>/dev/null || :
    semanage fcontext -d '%{_sharedstatedir}/xymon/www/rep(/.*)?'  2>/dev/null || :
    semanage fcontext -d '%{_sharedstatedir}/xymon/www/snap(/.*)?' 2>/dev/null || :
fi
%if %{with selinux}
if [ $1 -eq 0 ]; then
    for v in %{selinux_variants}; do
        semodule -s "$v" -r xymon >/dev/null 2>&1 || :
    done
fi
%endif

%files
%license COPYING
%doc README README.CLIENT RELEASENOTES CREDITS Changes
%{_mandir}/man*/*
%{_bindir}/xymon
%{_bindir}/xymoncmd
%{_sbindir}/xymonlaunch
%{_unitdir}/xymonlaunch.service
%dir %{dropindir}
%{serverconf}
%{_presetdir}/50-xymonlaunch.preset
%{_tmpfilesdir}/xymon.conf
%{_sysctldir}/70-xymon.conf
%config(noreplace) %{_sysconfdir}/sysconfig/xymonlaunch
%config(noreplace) %{_sysconfdir}/httpd/conf.d/xymon-apache.conf
%dir %{_sysconfdir}/xymon
%dir %{_sysconfdir}/xymon/tasks.d
%dir %{_sysconfdir}/xymon/web
%config(noreplace) %{_sysconfdir}/xymon/*
# Apache-writable overrides of the glob above (the later entry wins, as
# with logfetch below): the critical-editor CGI writes critical.cfg, and
# httpd reads the auth files the shipped apache config points at.
%config(noreplace) %attr(0644,apache,apache) %{_sysconfdir}/xymon/critical.cfg
%config(noreplace) %attr(0644,apache,apache) %{_sysconfdir}/xymon/critical.cfg.bak
%config(noreplace) %attr(0600,apache,apache) %{_sysconfdir}/xymon/xymonpasswd
%config(noreplace) %attr(0600,apache,apache) %{_sysconfdir}/xymon/xymongroups
%dir %{xymonhome}
%{xymonhome}/server
%exclude %{xymonhome}/server/bin/stackio
%exclude %{xymonhome}/server/bin/locator
%exclude %{xymonhome}/server/bin/tree
%exclude %{xymonhome}/server/bin/availability
%exclude %{xymonhome}/server/bin/loadhosts
%{xymonhome}/cgi-bin
%{xymonhome}/cgi-secure
# Static web content -- gifs, help, menu -- reached through symlinks in
# the www tree (see %%install).
%{_datadir}/xymon
# The embedded client: the same tree the build produces for the
# standalone package, shipped here because the server runs it on itself
# through tasks.cfg. One shared definition with %%files client (see the
# %%global at the top), so the two roles cannot drift.
%client_tree_filelist
%attr(0755,xymon,xymon) %dir %{_localstatedir}/log/xymon
%attr(-,xymon,xymon) %{_sharedstatedir}/xymon
%attr(0775,xymon,apache) %dir %{_sharedstatedir}/xymon/www/rep
%attr(0775,xymon,apache) %dir %{_sharedstatedir}/xymon/www/snap
%if %{with xymonping}
%attr(4750,root,xymon) %{xymonhome}/server/bin/xymonping
%endif
%if %{with selinux}
%{_datadir}/selinux/*/xymon.pp
%endif
# Reference only until the policy is reviewed and compiled (%%bcond selinux).
%doc xymon.te
%doc xymon-client.te
%doc bb.xml

%post client
# In a demotion the server package is still installed at this point, and
# with it its preset ("enable xymonlaunch.service"). Running the preset
# here would re-enable a unit the admin may have deliberately disabled,
# and would contradict this package's no-preset design (see %%files
# client). The %%preun guards already carry enablement across a swap, so
# there is nothing to preset.
if [ ! -e %{serverconf} ]; then
%systemd_post xymonlaunch.service
fi
# Upgrades from the old layout shipped xymon-client.service; that unit
# is gone, so carry its enablement and any running instance over to the
# shared name before clearing it. is-enabled and is-active are checked
# separately: an enabled-but-stopped client must stay enabled. Gated on
# the old unit file still being on disk, which is true only during the
# migrating upgrade itself -- without that this block would run on every
# future upgrade and stop an admin's own /etc/systemd unit of the same
# name.
if [ $1 -ge 2 ] && [ -e %{_unitdir}/xymon-client.service ]; then
    if systemctl is-enabled --quiet xymon-client.service 2>/dev/null; then
        systemctl --no-reload enable xymonlaunch.service >/dev/null 2>&1 || :
    fi
    if systemctl is-active --quiet xymon-client.service 2>/dev/null; then
        systemctl stop xymon-client.service >/dev/null 2>&1 || :
        systemctl start xymonlaunch.service >/dev/null 2>&1 || :
    fi
    systemctl --no-reload disable xymon-client.service >/dev/null 2>&1 || :
fi
%if %{with selinux}
for v in %{selinux_variants}; do
    semodule -s "$v" -i %{_datadir}/selinux/"$v"/xymon-client.pp >/dev/null 2>&1 || :
done
%endif
exit 0

%preun client
# Mirror of the server's guard: in a promotion (dnf swap xymon-client
# xymon) the server package is already installed when this runs, the
# unit's enablement must survive the client package's erase, and the
# running client is stopped here while client.conf still applies -- its
# cgroup kill is what stops the report script with it.
if [ -e %{serverconf} ]; then
    systemctl stop xymonlaunch.service >/dev/null 2>&1 || :
else
%systemd_preun xymonlaunch.service
fi

%postun client
%systemd_postun_with_restart xymonlaunch.service
%if %{with selinux}
if [ $1 -eq 0 ]; then
    for v in %{selinux_variants}; do
        semodule -s "$v" -r xymon-client >/dev/null 2>&1 || :
    done
fi
%endif
exit 0

%files client
%license COPYING
%doc README.CLIENT
# The same unit the server package ships -- one service name,
# xymonlaunch.service, on every host; xymonlaunch-run picks the role --
# plus the client role's drop-in. Deliberately NO preset: a fresh
# client must not start unconfigured against the baked-in 127.0.0.1,
# so enablement stays an explicit admin step.
%{_unitdir}/xymonlaunch.service
%dir %{dropindir}
%{clientconf}
%config(noreplace) %{_sysconfdir}/sysconfig/xymon-client
%dir %{xymonhome}
%client_tree_filelist
%attr(0755,xymon,xymon) %dir %{_localstatedir}/log/xymon
%if %{with selinux}
%{_datadir}/selinux/*/xymon-client.pp
%endif

%files client-local
%license COPYING
%{xymonhome}/server/bin/xymond_client
%{_mandir}/man8/xymond_client.8*
%{_mandir}/man5/analysis.cfg.5*

%files devel
%license COPYING
%dir %{_includedir}/xymon
%{_includedir}/xymon/include
%{_includedir}/xymon/lib
%dir %{_libdir}/xymon
%{_libdir}/xymon/*.a

%files tools
%license COPYING
%{xymonhome}/server/bin/stackio
%{xymonhome}/server/bin/locator
%{xymonhome}/server/bin/tree
%{xymonhome}/server/bin/availability
%{xymonhome}/server/bin/loadhosts

%changelog
