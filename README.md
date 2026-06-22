# MCreator Turbo

A small Windows tool that makes saving mod elements in MCreator 2025.2 (NeoForge) a lot faster on big workspaces.

> **Disclaimer:** This is an unofficial, third-party tool. It is **not affiliated with or endorsed by MCreator or Pylo**. It works by patching MCreator's behaviour at runtime, which is unsupported and could cause issues with your workspace or with MCreator itself. Use it at your own risk, and keep backups of your workspaces.

## Install

Download **[MCreator-Turbo-Installer.exe](https://github.com/ChickenNuggetAC/mcreator-turbo/releases/latest/download/MCreator-Turbo-Installer.exe)** and double-click it. Windows SmartScreen will warn because it is unsigned: click **More info**, then **Run anyway**.

Or download **[install.bat](https://github.com/ChickenNuggetAC/mcreator-turbo/raw/main/install.bat)** and run it; it downloads and launches the installer for you.

The `.ps1` files in this repo are the source, not the installer (double-clicking one just opens Notepad).

## launcher/

A settings app and installer (PowerShell/WinForms). It sets the JVM memory for the
editor and Gradle, picks a worker count, and attaches the fast-save agent when it
starts MCreator. `build-installer.ps1` builds the agent, assembles the payload, and
packages `Setup.exe`.

## agents/fastsave/

A `-javaagent` that skips the workspace-wide code regeneration MCreator runs on every
element save. Build and Run still regenerate, so mods stay correct; this just removes
the per-save lag on large workspaces.

## Building

Windows + PowerShell with MCreator installed (the scripts find it via `MCREATOR_HOME`
or the usual install paths and use its bundled JDK).

- agent: `agents/fastsave/build.ps1`
- installer: `launcher/build-installer.ps1`

## License

GPL-3.0. MCreator: https://mcreator.net/
