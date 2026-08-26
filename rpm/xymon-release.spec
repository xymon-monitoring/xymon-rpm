#
# Bootstrap package: configures the Xymon repository and installs the key
# used to verify it.
#
# Deliberately carries no %%{?dist} tag. It ships two text files and works
# identically on every EL and Fedora release, so one noarch package serves
# all of them -- and a single stable download URL is much easier to put in
# documentation than one per distribution.
#
Name:           xymon-release
# A published NEVRA is immutable: bump Version whenever the repo file or
# the key changes, or the publish step will refuse to ship the new copy.
Version:        2
Release:        1
Summary:        Xymon repository configuration and signing key
License:        GPL-2.0-only
URL:            https://github.com/xymon-monitoring/xymon-rpm
BuildArch:      noarch

# The server package requires fping, which exists only in EPEL on EL. Weak,
# not strong, on purpose: this is one noarch build for every EL and Fedora,
# and Fedora ships no epel-release at all -- an unsatisfiable Recommends is
# skipped there, where an unsatisfiable Requires would break the package.
Recommends:     epel-release

Source0:        xymon.repo
Source1:        RPM-GPG-KEY-xymon

%description
Installs the package repository configuration for Xymon, along with the
GPG key its packages and repository metadata are signed with.

HIGHLY EXPERIMENTAL: this packaging is new and has seen no production
use. Layout, versioning and repository structure may still change
without notice.

Two repositories are configured. The stable one, built from tagged
releases, is enabled. Development snapshots built from the tip of the
development branch are configured but disabled; enable them per host with

    dnf config-manager --set-enabled xymon-snapshot

%prep
%autosetup -c -T

%install
install -Dpm 0644 %{SOURCE0} %{buildroot}%{_sysconfdir}/yum.repos.d/xymon.repo
install -Dpm 0644 %{SOURCE1} \
    %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-xymon

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/xymon.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-xymon

%changelog
