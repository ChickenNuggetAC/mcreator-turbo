# MCreator Turbo

Performance tooling for MCreator 2025.2 (NeoForge) on Windows.

## launcher/

A settings app and installer (PowerShell/WinForms). It sets the JVM memory for the
editor and Gradle, picks a worker count, and attaches the two agents below when it
starts MCreator. `build-installer.ps1` builds the agents, assembles the payload, and
packages `Setup.exe`.

## agents/fastsave/

A `-javaagent` that skips the workspace-wide code regeneration MCreator runs on every
element save. Build and Run still regenerate, so mods stay correct; this just removes
the per-save lag on large workspaces.

## agents/parallelregen/

A `-javaagent` that swaps six MCreator classes for parallel-regeneration variants. A
class is only swapped when its SHA-256 matches the pinned build (2025.2.28610); on any
other build it does nothing. The patched classes ship precompiled under `resources/`,
so the build needs nothing but a JDK.

## Building

Windows + PowerShell with MCreator installed (the scripts find it via `MCREATOR_HOME`
or the usual install paths and use its bundled JDK).

- agents: `agents/<name>/build.ps1`
- installer: `launcher/build-installer.ps1`

## License

GPL-3.0. The regen agent includes a modified copy of MCreator's
`RegenerateCodeAction.java` (Copyright Pylo and contributors, GPL-3.0).
MCreator: https://mcreator.net/
