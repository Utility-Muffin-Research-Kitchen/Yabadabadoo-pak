# Licences and provenance

| What | Licence | In the pak |
| --- | --- | --- |
| This repository's build and packaging code | MIT | `LICENSES/REPO-LICENSE.txt` here |
| Yabadabadoo `v0.2` (patched) | GPL-2.0-or-later | `licenses/Yabadabadoo-COPYING.txt`, `licenses/Yabadabadoo-THIRD-PARTY-NOTICES.txt` |
| RetroArch `v1.22.2` (patched) | GPL-3.0-or-later | `licenses/RetroArch-COPYING.txt` |
| Debian bookworm armhf libraries (glibc, libstdc++, SDL2, PulseAudio client, and their dependencies) | per package, mostly LGPL/MIT/BSD-style | `licenses/debian/<package>.copyright` |
| Rockchip Mali G52 userspace driver (`libmali-bifrost-g52-g13p0-wayland-gbm`) | Arm Mali userspace driver EULA | `licenses/mali/libmali-rockchip-debian-copyright` |

`licenses/runtime-manifest.json` lists every file in `runtime/lib`: its size,
SHA-256 and the Debian package it came from, with that package's version,
source package and a `snapshot.debian.org` link to the exact source.
`BUILD-INFO.json` records the upstream commits and the SHA-256 of the built
RetroArch and core.

## GPL obligations

Yabadabadoo and RetroArch are modified (see `patches/`), so every release
publishes the corresponding source beside the pak:
`yabadabadoo-pak-source.tar.gz` from `make dist-source`. It holds this
repository and the patched Yabadabadoo and RetroArch trees exactly as they were
built.

The Debian libraries are shipped unmodified, at the versions the runtime
manifest names; their source is the matching Debian source package.

## The Mali driver

The Mali driver is closed-source Arm software, redistributed under its EULA
from the pinned `tsukumijima/libmali-rockchip` armhf package. The build checks
the package, the driver and its licence text against the SHA-256 values in
`upstream.lock.json`, and the pak must carry
`licenses/mali/libmali-rockchip-debian-copyright`: `make check-package` fails
without it.
