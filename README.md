# Yabadabadoo-pak

**Experimental.** An optional [Pak Rat](https://github.com/Utility-Muffin-Research-Kitchen/leaf-docs)
content pak for Leaf on the Miniloong Pocket 1 that adds
[Yabadabadoo](https://github.com/ProRapSuperstarOriginalMaster/Yabadabadoo), a
Sega Saturn core tuned for low-power handhelds, as an alternate core for the
Sega Saturn system.

Yabadabadoo is by
[ProRapSuperstarOriginalMaster](https://github.com/ProRapSuperstarOriginalMaster),
a fork of the libretro port of Yabause. Its upstream README describes it as
early and largely AI-assisted work, so expect some games to glitch, run slowly
or not start. This pak packages upstream `v0.2` for Leaf; it doesn't change
how the emulator behaves beyond the patches listed under [Patches](#patches).

## What you get

There is no app to open and no new tile. Installing the pak adds
**Yabadabadoo (experimental)** to the Sega Saturn core picker, and you choose
it per system or per game. YabaSanshiro stays the default, and your existing
core choices keep working.

Yabadabadoo runs Saturn games (`.chd`, `.cue`, `.iso`, `.mds`, `.ccd`, `.m3u`,
`.zip`) from `Roms/SATURN/`.

## BIOS

Yabadabadoo needs a real Saturn BIOS. Put one of these in `BIOS/SATURN/` on the
card the game is on:

| File | Region | MD5 |
| --- | --- | --- |
| `sega_101.bin` | Japan v1.01 | `85ec9ca47d8f6807718151cbcca8b964` |
| `mpr-17933.bin` | USA/Europe v1.00 | `3240872c70984b6cbfda1586cab68dbe` |
| `saturn_bios.bin` | either of the above, renamed | |

It picks the BIOS that matches the game's region on its own. Without one it
shows a screen asking for a BIOS instead of starting the game.

## Controls

The face buttons follow the shape of a Saturn pad. **Y**, **B** and **A**, left
to right around your thumb, are the Saturn's A, B and C row, and **L1**, **X**
and **R1** are its X, Y and Z row:

| Saturn | Handheld |
| --- | --- |
| A, B, C | **Y**, **B**, **A** |
| X, Y, Z | **L1**, **X**, **R1** |
| L, R | **L2**, **R2** |
| Start | **Start** |

To move a button for one game or for every game, open RetroArch's menu, go to
**Quick Menu > Controls**, change it, and save a game or core remap file.

- **MENU** opens RetroArch's menu, where you'll find save states, core options
  and **Quit RetroArch**.
- Holding **MENU** for 3 seconds quits back to Leaf.
- With a controller connected, it's player 1, as everywhere else in Leaf, and
  its Guide or Home button opens RetroArch's menu instead.
- The settings you change in Leaf's **RetroArch Settings**, the display options
  and the button mapping, also apply here. Yabadabadoo reads them every time it
  starts.
- Hotkeys you bind in Leaf's RetroArch don't apply here yet.

Leaf's own in-game menu isn't available with this core: Yabadabadoo runs in its
own RetroArch, not Leaf's.

## Where your data lives

- In-game saves (the Saturn's backup memory): `Saves/Yabadabadoo/<game>.srm`
  on the game's card. They're written a second after the game saves, so a crash
  or a power cut keeps them.
- Save states: `States/Yabadabadoo/` on the game's card.
- Core options, per-game overrides and remaps:
  `.userdata/mlp1/Yabadabadoo/config/` on the primary card.
- The last session's log: `.userdata/mlp1/logs/yabadabadoo.log`.

Changes you save from inside Yabadabadoo's RetroArch don't persist, and they
don't reach Leaf's RetroArch. Core options, overrides and remaps do. Change
everything else in Leaf's **RetroArch Settings**.

Version 0.2.0 kept its own `retroarch.cfg` in `.userdata/mlp1/Yabadabadoo/`.
Nothing reads it any more, and you can delete it.

Saves and states are separate from YabaSanshiro's, so switching cores doesn't
carry progress across.

## Known limits

- It's experimental: see the
  [upstream release notes](https://github.com/ProRapSuperstarOriginalMaster/Yabadabadoo/releases)
  for the games known to have problems.
- No RetroAchievements, Leaf in-game menu, boot resume or save state on power
  hold.
- Leaf's swap of the menu's OK and Cancel buttons and its Bluetooth audio
  routing aren't applied here.
- The pak is about 71 MB installed, most of it the 32-bit graphics driver it
  has to bring along.

## How it's put together

Yabadabadoo's SH-2 recompiler, which most of its speed comes from, exists only
for 32-bit ARM. The MLP1's kernel runs 32-bit ARM programs, but Leaf's
RetroArch and the rest of the system are 64-bit, and the rootfs has no 32-bit
libraries. So the pak brings its own 32-bit world:

- `bin/retroarch`: upstream RetroArch `v1.22.2` built for armhf (SDL2,
  EGL/GLES on Wayland, PulseAudio), with one patch.
- `cores/yabadabadoo_libretro.so`: Yabadabadoo `v0.2` built for armhf with its
  recompiler.
- `runtime/lib/`: the 32-bit dynamic loader and every library the two load,
  from Debian bookworm armhf, plus the Rockchip Mali G52 32-bit driver.
- `scripts/run.sh`: the core Leaf launches. It runs RetroArch through the
  bundled loader as a Wayland client, with Leaf's saves, states and BIOS
  folders, Leaf's controller profile and a RetroArch config it builds from
  Leaf's own settings files on every launch.

Nothing depends on PortMaster or any other pak.

### Patches

- `patches/retroarch/0001-sdl-gl-apply-attributes-after-video-init.patch`:
  RetroArch sets SDL's GL context attributes before SDL's video subsystem
  starts, so SDL drops them. Leaf's 64-bit SDL happens to default to GLES 2;
  Debian's defaults to desktop GL, which Mali can't create, and RetroArch got
  an OpenGL ES 1.1 context. The patch applies them again after SDL starts.
- `patches/yabadabadoo/0001-flush-backup-ram-when-idle.patch`: the core wrote
  backup memory to disk only when it unloaded. It now writes it once the game
  has stopped writing for a second.
- `patches/yabadabadoo/0002-reset-boots-the-inserted-disc.patch`: after a
  disc swap, a reset rebooted the first disc. It now boots the disc in the
  drive, as a Saturn does.
- `patches/yabadabadoo/0003-face-buttons-follow-the-saturn-pad.patch`: the
  core put the Saturn's A, B and C on B, A and R1, the usual libretro layout,
  which copies Street Fighter II on the SNES. It now puts them on Y, B and A,
  in the same order as on a Saturn pad, and X, Y and Z on L1, X and R1.

## Building

You need Docker, git and python3. Everything else is fetched at pinned
versions (`upstream.lock.json`) and built in a digest-pinned Debian bookworm
image.

```sh
make package        # build/package/Yabadabadoo.pak
make dist-pakrat    # build/dist/Yabadabadoo.mlp1.pak.zip
make dist-source    # build/dist/yabadabadoo-pak-source.tar.gz
make check          # manifest against CONTENT-1, and the wrapper test
make check-package  # the built package, strictly
```

## Licence

The build and packaging code in this repository is MIT
(`LICENSES/REPO-LICENSE.txt`). The pak redistributes GPL software and a
proprietary GPU driver; see `LICENSES/README.md`.
