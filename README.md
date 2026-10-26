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
or not start. This pak packages upstream `v0.3` for Leaf; it doesn't change
how the emulator behaves beyond the patches listed under [Patches](#patches).

**Needs Leaf 0.13.0 or later.** Since version 0.3.0, the pak has Leaf run its
RetroArch like its own, which older Leaf releases can't do, so Pak Rat
doesn't offer it to them. 0.2.0, which ran on Leaf 0.12, was never published.
The gate can't name a beta: Leaf drops any `-beta.N` from its own version
before comparing it with `min_leaf_version`, so the 0.13.0 betas that came out
before this support pass the gate too. They install the pak, then reject its
manifest (`unknown-field` on `frontend`), and Yabadabadoo doesn't show up as a
core until Leaf is updated.

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

To move a button for one game or for every game, open **RetroArch Settings**
in the in-game menu, go to **Quick Menu > Controls**, change it, and save a
game or core remap file.

Everything else plays like the other cores you run through Leaf's RetroArch,
because it is driven by the same Leaf code with the same controls:

- Tap **MENU** to open Leaf's in-game menu over the game: **Continue**,
  **Save State**, **Load State**, **Reset**, **Performance**,
  **RetroArch Settings** and **Save & Quit**.
- **MENU** plus a button is a RetroArch hotkey, with the hotkeys you set in
  RetroArch, exactly as with other cores. **MENU + SELECT** opens the game
  switcher and **MENU + L1** takes a screenshot, unless you've moved them.
- Holding the power button saves a state, and Leaf resumes the game at the
  next boot.
- With a controller connected, it's player 1, as everywhere else in Leaf, and
  its Guide or Home button opens the in-game menu.
- RetroArch's own menu is under **RetroArch Settings** in the in-game menu. A
  multi-disc game (`.m3u`) swaps discs there, under **Quick Menu > Disc
  Control**.

## Where your data lives

- In-game saves (the Saturn's backup memory): `Saves/Yabadabadoo/<game>.srm`
  on the game's card. They're written a second after the game saves, so a crash
  or a power cut keeps them.
- Save states: `States/Yabadabadoo/` on the game's card.
- Core options, core overrides and remaps: `.umrk/mlp1/retroarch/config/Yabadabadoo/`
  on the primary card, next to those of Leaf's other RetroArch cores.
- Everything else RetroArch remembers is Leaf's RetroArch configuration, which
  this core shares: a setting you change in **RetroArch Settings** applies to
  every RetroArch core, this one included. Leaf only writes changes made in
  this core back to that configuration while this RetroArch is the same
  version as Leaf's own.

Saves and states are separate from YabaSanshiro's, so switching cores doesn't
carry progress across.

### Coming from 0.3.0

0.3.1 moves Yabadabadoo from upstream `v0.2` to `v0.3`. Your in-game saves,
save states and settings carry over, and states saved with 0.3.0 load. A state
saved with 0.3.1 doesn't load in 0.3.0, so if you go back to 0.3.0, load a state
you saved before updating, or continue from your in-game save.

### Coming from 0.2

0.2.0 was only ever a development build, but anyone who sideloaded it keeps
their data. Saves and save states are in the same folders and carry over as they are. The
first time you launch Yabadabadoo after updating, the core options, core
overrides and remaps 0.2 kept in `.userdata/mlp1/Yabadabadoo/config/` are
copied to the new folder above. Files already there are never replaced, and
the old folder is left alone: it's safe to delete once you're happy. 0.2's own
`retroarch.cfg` isn't copied, because the shared Leaf configuration replaces it.

## Known limits

- It's experimental: see the
  [upstream release notes](https://github.com/ProRapSuperstarOriginalMaster/Yabadabadoo/releases)
  for the games known to have problems.
- Recording (**MENU + R1**) isn't available with this core. Its RetroArch is
  built without FFmpeg, which recording needs.
- Bluetooth audio isn't available with this core. Its 32-bit RetroArch plays
  through the device's own audio output only.
- No RetroAchievements yet.
- The pak is about 71 MB installed, most of it the 32-bit graphics driver it
  has to bring along.

## How it's put together

Yabadabadoo's SH-2 recompiler, which most of its speed comes from, exists only
for 32-bit ARM. The MLP1's kernel runs 32-bit ARM programs, but Leaf's
RetroArch and the rest of the system are 64-bit, and the rootfs has no 32-bit
libraries. So the pak brings its own 32-bit world, and its own RetroArch that
Leaf launches in place of the one it ships.

Leaf starts that RetroArch exactly like its own: the same arguments, the same
generated configuration and the same controls, and its in-game menu, game
switcher, save state on power hold and boot resume talk to it over RetroArch's
network command port. The pak declares this in `pak.json` as a `retroarch`
core with a `frontend` (protocol `leaf-ra-1`) instead of the standalone `path`
core 0.2 used. For that to work, the RetroArch has to understand Leaf's
commands, so it's built with the same patches as Leaf's own.

- `bin/retroarch`: upstream RetroArch `v1.22.2` built for armhf (SDL2,
  EGL/GLES on Wayland, PulseAudio), with Leaf's MLP1 patches and one more.
- `cores/yabadabadoo_libretro.so`: Yabadabadoo `v0.3` built for armhf with its
  recompiler.
- `info/yabadabadoo_libretro.info`: the core's metadata, copied from
  Yabadabadoo's source when the pak is built. Its `corename` is the name
  RetroArch files saves and states under, and equals `config_folder` in
  `pak.json`.
- `runtime/lib/`: the 32-bit dynamic loader and every library the two load,
  from Debian bookworm armhf, plus the Rockchip Mali G52 32-bit driver.
- `scripts/retroarch.sh`: the frontend Leaf launches. It passes Leaf's
  arguments straight through and only sets up the 32-bit side: it drops Leaf's
  64-bit library path and preloads, makes RetroArch a Wayland client of the
  bundled graphics driver, points it at Leaf's audio server, and runs it
  through the bundled loader. It writes no configuration of its own (Leaf
  supplies the config and the controller profile), and it does the one-time
  move of 0.2's settings described above.

Nothing depends on PortMaster or any other pak. There's no separate log file
any more: RetroArch's output goes where it does for Leaf's own RetroArch.

### Patches

RetroArch gets two sets, in this order.

**Leaf's MLP1 set**, in `patches/retroarch/leaf/`, copied unchanged from
[retroarch-builds](https://github.com/Utility-Muffin-Research-Kitchen/retroarch-builds)
at commit `a4c198d` and applied in the order of Leaf's
`config/mlp1-retroarch-patch-set.txt`. Leaf pins no retroarch-builds commit (it
builds from a checkout), so this is `main` at the time of writing. `SOURCE.json`
there records each patch's original path, its order and its sha256, and
`make check-patches` fetches that commit and fails if any copy has drifted. CI
runs it too.

| Patch | What it's for |
| --- | --- |
| `01-portrait-rotation` | rotate RetroArch's landscape output for the portrait panel |
| `02-command-menu` | the command-port commands behind Leaf's in-game menu: pause, open menu, state slots and saves, disc control, shaders, status |
| `03-jawaka-load-content` | switch to another game without restarting RetroArch (game switcher) |
| `04-controller-bindings` | label bindings with the controller's own button names |
| `05-record-scale-clamp` | clamp the recording scale to the core's real size |
| `06-record-indicator` | draw a pulsing dot while recording |
| `07-wayland-swap-interval` | honor swap intervals above 1 on SDL/Wayland |

All seven apply, and compile, unchanged with this build's options. The
recording ones have nothing to act on without FFmpeg, but stay in so the source
is Leaf's. None was dropped.

**This pak's own**, in `patches/retroarch/pak/`:

- `0001-sdl-gl-apply-attributes-after-video-init.patch`: RetroArch sets SDL's GL
  context attributes before SDL's video subsystem starts, so SDL drops them.
  Leaf's 64-bit SDL happens to default to GLES 2; Debian's defaults to desktop
  GL, which Mali can't create, and RetroArch got an OpenGL ES 1.1 context. The
  patch remembers the request in `bind_api` and applies it again after SDL
  starts. It's written to apply after `07-wayland-swap-interval`, which edits
  the same function. Leaf's own 64-bit RetroArch has the same latent bug, so
  the fix is also being added to retroarch-builds as `sdl-gl-attributes`; when
  this pak next copies in Leaf's set and it contains that patch, delete this
  one.

Three patches change Yabadabadoo itself, in `patches/yabadabadoo/`:

- `0001-flush-backup-ram-when-idle.patch`: the core wrote backup memory to disk
  only when it unloaded. It now writes it once the game has stopped writing for
  a second.
- `0002-reset-boots-the-inserted-disc.patch`: after a disc swap, a reset
  rebooted the first disc. It now boots the disc in the drive, as a Saturn
  does.
- `0003-face-buttons-follow-the-saturn-pad.patch`: the core put the Saturn's
  A, B and C on B, A and R1, the usual libretro layout, which copies Street
  Fighter II on the SNES. It now puts them on Y, B and A, in the same order
  as on a Saturn pad, and X, Y and Z on L1, X and R1.

## Building

You need Docker, git and python3. Everything else is fetched at pinned
versions (`upstream.lock.json`) and built in a digest-pinned Debian bookworm
image.

```sh
make package        # build/package/Yabadabadoo.pak
make dist-pakrat    # build/dist/Yabadabadoo.mlp1.pak.zip
make dist-source    # build/dist/yabadabadoo-pak-source.tar.gz
make check          # manifest against CONTENT-1, the wrapper test, the patch copies
make check-patches  # fetch retroarch-builds and compare Leaf's vendored patches
make check-package  # the built package, strictly
```

`make check` and `make check-package` read the content-pak contract from a
pinned [leaf-contracts](https://github.com/Utility-Muffin-Research-Kitchen/leaf-contracts)
commit, which has the `frontend` field 0.3.0 introduced. To check against a
local clone instead, pass it in:
`make check CONTRACT_DIR=/path/to/leaf-contracts`.

## Licence

The build and packaging code in this repository is MIT
(`LICENSES/REPO-LICENSE.txt`). The pak redistributes GPL software and a
proprietary GPU driver; see `LICENSES/README.md`.
