# Changelog

All notable changes to **mob_location** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [0.1.1] - 2026-06-15

### Added
- Bundled `MobLocation.DemoScreen` — a ready-to-run sample (get-once / start / stop, live coords) declared in the manifest's `:screens`, so a generated app can kick the tires on activation. It's pure-Elixir and hot-pushable; the plugin is now tier 3 (NIF + screens). Delete the screen + its `:screens` entry in a real app.

## [0.1.0] - 2026-06-12

Initial release. Device location (GPS / network) for Mob apps.

- `MobLocation.start/2` / `stop/1` with updates delivered via `handle_info`.
- Extracted from mob core in the 0.7.0 plugin-extraction wave.
- Requires `mob ~> 0.7`.
