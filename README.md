# M3U8 Studio — Flutter Windows Edition

A dark, Windows-focused IPTV playlist and stream tester based on four interface reference images. Developed for **Md Jahidul Islam**.

## Features

- Five screens: Dashboard, ID Range Tester, File / URL Tester, Playlist & Player Studio, Json Spliter.
- URL pattern placeholders: `{id}`, `{cdn-numer}` (also `{cdn-number}`), `{ip}`, `{port}`.
- Numeric ranges, random IDs, pasted/uploaded ID lists, inclusive IPv4 ranges and port ranges.
- No fixed 5,000-link generation cap, with duplicate removal; jobs are limited in practice by device memory and CPU.
- Import `.m3u`, `.m3u8`, `.json`, `.txt` files, paste playlists or a direct stream URL; fetch remote `.m3u`/`.json`/`.txt` playlists and extensionless playlist links.
- Large local playlist and JSON parsing runs in a background isolate; file selection does not paste the entire file into the input box.
- Read common IPTV JSON fields, including `name`, `logo`, `group`, `url`, and `epg_id`.
- HTTP availability checker with fast HEAD-only mode or HEAD/limited GET fallback, adjustable concurrent workers, stop button, progress and logs. Quick Check now checks the entire loaded list.
- Embedded mpv-based player with Play/Pause/Stop and volume. Entries are added to the export list when the player reports that playback started.
- Rename/reorder/remove export entries; save as M3U.
- Json Spliter: inspect root array/object or wrapper arrays, split by number of parts or items per part, preserve wrapper metadata and JSON validity, keep formatting/pretty/minify, export individual files, all parts, or compressed ZIP.

### Important distinction

`HTTP OK` only means the URL returned a successful HTTP status; it does **not** guarantee decodable video. `Playback started` means the media player raised its playing event, which is a useful heuristic but **not** a frame-by-frame proof that playback is healthy. Check the preview before exporting important channels.

The app has no remote license activation, bundled IPTV accounts, stream credentials or preloaded channels. Only test streams you have permission to access.

## Build on GitHub (no local Flutter setup needed)

1. Create a **new GitHub repository** (for example `M3U8-Studio`).
2. Upload **all contents of this project** to the repository root, including `.github/workflows/windows-build.yml`.
3. Open **Actions → M3U8 Studio - Windows x64 → Run workflow**. A push to `main` or `master` also starts a build.
4. Wait for the workflow to complete. Open the workflow run and download the `M3U8-Studio-Windows-x64` artifact.
5. Extract `M3U8-Studio-Windows-x64.zip` and run `m3u8_studio.exe` from the extracted folder.

**Do not distribute only the `.exe`:** keep its `data` directory and DLL files together. The artifact contains the portable release folder.

The workflow generates the standard Flutter Windows native runner on the Windows GitHub runner, runs `flutter analyze` and `flutter test`, builds the release, and zips the complete runner output. No API keys or GitHub secrets are required.

## Local Windows development

Install Flutter stable, Visual Studio with **Desktop development with C++**, and Git. In the project directory run:

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name=m3u8_studio .
flutter pub get
flutter test
flutter analyze
flutter run -d windows
```

Release build:

```powershell
flutter build windows --release
```

The CI output path is `build/windows/x64/runner/Release`.

## Structure

```text
lib/
  main.dart                  Application entry point
  core/
    channel.dart             Channel metadata and M3U serialization
    playlist_parser.dart     M3U/JSON parsing, URL validation, deduplication
    range_generator.dart     Numeric/IP/port combinations
    json_splitter_service.dart  Split JSON and create ZIP archives
    stream_checker.dart      Bounded HTTP reachability tests
  ui/
    studio_app.dart          Five-page Windows-style UI and media player
    json_splitter_page.dart  JSON split UI and exports
test/
  playlist_parser_test.dart
  range_generator_test.dart
  json_splitter_test.dart
.github/workflows/windows-build.yml
```

## Known limitations

- The release workflow targets **64-bit Windows**. Native 32-bit Windows builds are not supplied.
- Some providers block HEAD, require special headers/tokens, use geo-restrictions, or time out. HTTP check results may be inconclusive.
- Player codec support depends on the native media-kit libraries and the stream format.
- There is no hardcoded file-size or link-count limit; very large inputs still require enough RAM, storage, time, and network bandwidth.
- Test a few streams first; testing thousands of URLs can take considerable time and may be disallowed by service operators. Adjustable concurrency should be used responsibly.
- No permanent library/database is included: export verified streams before closing the app.
- The native Windows runner is generated during the build to avoid shipping version-specific generated code.

## License

Source files in this starter project may be used and modified for your own app. Third-party Flutter packages and native playback libraries retain their own licenses.
