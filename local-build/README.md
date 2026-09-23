# Local build of File Converter

This folder rebuilds File Converter from this source tree and installs it over the official **2.2** release.
Visual Studio is not needed: only the .NET 8 SDK that is already on this PC.

## What this build changes (see `CHANGELOG.md`, section *Unreleased*)

- **Animated WebP.** Every webp preset (To Webp, Scale 75%, Scale 25%, Rotate left, Rotate right) also accepts
  videos and gifs, and keeps every frame: ffmpeg's `libwebp_anim` encoder writes a looping animated webp. The
  preset settings apply (quality, scale, rotation, size clamps) plus a new **Frames per second** setting
  (15 by default, same as To Gif). Still images still go through ImageMagick exactly as before.
- **ffmpeg conversions no longer hang.** Official 2.2 passes `-progress pipe:1` to ffmpeg but never reads that
  pipe, so any ffmpeg conversion running longer than a few seconds (VP9 webm, long gifs...) blocks forever.
- **Office conversions work.** The official 2.2 installer does not ship the NetOffice DLLs that the Word, Excel
  and PowerPoint conversions load; `deploy.ps1` copies them in.
- **Rotate left/right turn still images the labelled way.** Official 2.2 hands the counter-clockwise rotation
  setting to ImageMagick, which rotates clockwise, so "Rotate left" turned photos right (videos were correct).

## Rebuild and install

1. Install the official File Converter 2.2 first (this build compiles against its DLLs).
2. In PowerShell 7, from this folder:

   ```
   .\build.ps1
   .\deploy.ps1
   ```

`build.ps1` mirrors `Application\FileConverter` into `%TEMP%\FileConverter-local-build`, generates an SDK-style
project from the file list of the original `FileConverter.csproj`, and builds it. The first build restores
Microsoft.NETFramework.ReferenceAssemblies 1.0.3 and NetOffice 1.7.4.11 from nuget.org.

`deploy.ps1` asks for administrator rights once, backs up every file it replaces into `..\backups`, copies the
new files, verifies them, then refreshes the built-in presets in your user settings (your settings file is
backed up first). Like the official installer, that refresh keeps custom presets and resets edits made to
built-in presets; add `-SkipPresetRefresh` to leave them alone.

## Good to know

- The shell extension (`FileConverterExtension.dll`) is unchanged; it reads the presets from your settings, so
  no Explorer restart is needed.
- An official upgrade (File Converter offers one when a new version is out) replaces this build. Check whether
  the new version has these fixes before accepting, or rebuild from the new source.
- ffmpeg 8 cannot decode animated webp, so a webp made here cannot be converted back through ffmpeg presets.
