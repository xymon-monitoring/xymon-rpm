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
Version:        6
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

Four repositories are configured. The stable one, built from tagged
releases, is enabled. Development snapshots built from upstream main,
previews of the next release alone (xymon-preview-next) and previews of
every unreleased milestone (xymon-preview) are configured but disabled;
enable one per host by setting enabled=1 in /etc/yum.repos.d/xymon.repo,
or with the command your dnf understands, naming the repository:

    dnf config-manager --set-enabled xymon-snapshot          (dnf4, EL)
    dnf config-manager setopt xymon-snapshot.enabled=1       (dnf5, Fedora)
    dnf config-manager --set-enabled xymon-preview-next      (dnf4, EL)
    dnf config-manager setopt xymon-preview-next.enabled=1   (dnf5, Fedora)

Enable one pre-release repository at a time: a snapshot of the same
version sorts above a preview, so dnf would install the snapshot.

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
