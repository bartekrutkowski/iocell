iocell
======

**A FreeBSD jail manager using ZFS, VNET and resource limits.**

iocell continues the classic shell-based iocage interface. Jails can use
shared-IP networking or a separate VNET stack, shared read-only base files,
ZFS clones, templates, snapshots, quotas and optional kernel resource limits.
Configuration is stored in UCL files alongside the ZFS datasets; native ZFS
properties still control storage settings.

## Status

The current safety fixes were verified on **FreeBSD 15.1-RELEASE-p6/amd64**,
including 14.5-RELEASE jail fixtures. This is not a compatibility guarantee for
all other host releases or architectures. Use a FreeBSD release still receiving
security support and test upgrades on a disposable host first.

There are remaining command limitations. Read the
[known issues](doc/source/known-issues.rst),
[historical command audit](doc/command-audit-2026-10-29.md), and
[safety-fix verification](doc/safety-fixes-2026-10-30.md) before production use.
The `develop` branch may contain experimental work and unqualified migrations.

## Requirements and installation

- FreeBSD with ZFS and jail support, and at least one usable ZFS pool.
- `uclcmd` (the `devel/uclcmd` port/package); this is not a zero-dependency tool.
- Root for mutating commands; supported read-only commands can run unprivileged.
- VNET kernel support for VNET jails. Shared-IP jails do not require it.
- RACCT/RCTL kernel support and `kern.racct.enable=1` at boot for resource limits.
- Git for Git-backed workflows; SSH keys for remote operations. `mbuffer` is
  optional and must be available at both ends when selected by remote send.

The FreeBSD port is `sysutils/iocell`:

```sh
pkg install iocell
```

A packaged release may not include fixes in this checkout. To exercise the
checkout directly on FreeBSD, install its dependencies and use `sh ./iocell`
from the repository root in place of the installed `iocell` command.

## Quick start

Use a dedicated test pool initially. The example assumes the installer-created
pool `zroot`; substitute your actual pool name.

```sh
iocell activate zroot
iocell fetch release=15.1-RELEASE
iocell create release=15.1-RELEASE tag=myjail vnet=off \
    ip4_addr="em0|192.168.1.10/24"
iocell start myjail
iocell console myjail
```

Choose an available release compatible with your host. Specify it explicitly:
the interactive fetch menu is obsolete and can reject its own current-host
default. Use an appropriate distribution mirror if its default location is no
longer available; see [basic usage](doc/source/basic-use.rst).

Replace `em0` with the host interface shown by `ifconfig(8)` and select an unused
address on your own network. `vnet=off` is explicit because VNET-capable hosts
otherwise enable VNET automatically. This creates a **basejail**, not a complete
independent OS copy. Basejails depend on their fetched shared release.

For VNET, configure an appropriate bridge and routing/firewall policy first;
see [networking](doc/source/networking.rst). Do not bridge jail interfaces onto
a provider's public link if additional MAC addresses are prohibited. An isolated
private bridge with host routing/NAT avoids exposing those MACs externally.

## Commands and workflows

Use the canonical command reference rather than old command lists:

```sh
iocell help
```

The reference is maintained in [lib/ioc-help](lib/ioc-help); `iocell.8` and
`iocell.8.txt` are generated from that text. Full UUIDs and tags are supported;
do not rely on short UUID prefixes except for image selection during import.

- [Basic usage and package installation](doc/source/basic-use.rst)
- [Jail types](doc/source/jailtypes.rst)
- [Templates](doc/source/templates.rst)
- [Snapshots, rollback, updates and resource limits](doc/source/advanced-use.rst)
- [Operational guidance](doc/source/best-practices.rst)
- [Tests and destructive-test prerequisites](tests/README.md)

Useful distinctions:

- `create` creates a basejail; `create -e` creates an empty filesystem, not a
  clone. Legacy `create -b`, `-c`, `-t` and `base=` recipes are not supported.
- `clone TAG@snapshot tag=newtag` uses an existing root snapshot.
- `restart TAG` is a hard stop/start; `restart -s TAG` requests a soft restart.
- Template names must be valid safe ZFS components. Retag generated timestamp
  names before conversion. Invalid names fail before metadata/alias changes.
- Full sends take fresh unique snapshots. `send -m` removes only the original
  source after successful receive and activation. Existing replicas generally
  need incremental streams, not a forced full replacement.
- Non-force `clean -t` protects dependent clones; explicit `-f` permits their
  destruction. All cleanup operations are destructive.
- Historical `chroot`, `record`, `package` and `show` subcommands are not
  dispatched. Use the documented current workflows instead.

## Reporting issues and contributing

Open issues at <https://github.com/bartekrutkowski/iocell/issues> with the command,
complete output, `uname -ro`, jail type, relevant properties, and expected versus
observed state. Include `iocell version` and the checkout's `git rev-parse HEAD`
or installed package version.

Please open upstream pull requests against `develop` and follow
[CONTRIBUTING.md](CONTRIBUTING.md). Update `lib/ioc-help` before regenerating the
manuals. The [test guide](tests/README.md) distinguishes portable tests from
opt-in FreeBSD/ZFS tests; never run the latter against production data.
