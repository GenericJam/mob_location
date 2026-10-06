# Changelog

All notable changes to **mob_location** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [0.1.6] - 2026-10-06

### Fixed

- **Android: a failed Fused location call answers the caller; the bridge
  passes `./gradlew :app:lintRelease`** (MOB-401). `get_once/1` and `start/2`
  ignored a failed `lastLocation` / `requestLocationUpdates` (no failure
  listener), so the caller never got a reply. A failure now delivers
  `{:location, :error, :permission_denied}` for a `SecurityException` and
  `{:location, :error, :unavailable}` for any other failure; a failed
  `start/2` leaves no callback registered. A request the OS leaves pending
  (seen with Play services disabled or the location app-op denied) still
  gets no reply (MOB-403). The calls also
  handle a synchronous `SecurityException` explicitly, which clears the three
  `MissingPermission` errors that failed a host app's release lint. No change
  when the calls succeed.

## [0.1.5] - 2026-10-04

### Fixed

- **iOS: every `Mob.Permissions.request(socket, :location)` gets exactly one
  answer, to its own pid** (MOB-391). The permission handler kept one global
  delegate holding one pid, so a second request while the dialog was up
  replaced the first requester, which never got an answer. And it relied on
  `requestWhenInUseAuthorization` calling the delegate, which iOS does only
  while the status is still undecided, so a request after the user had
  answered could go unanswered. The handler now answers a decided status at
  once and keeps every requester that arrives while the dialog is up,
  answering all of them when the user decides. Approximate location ("Precise"
  off) is still `:granted`.
- Android needs no change here: the generated app's permission queue (mob_new
  0.6.6, MOB-391) now reports a coarse-only (Approximate) grant as
  `{:permission, :location, :granted}`, so the note under 0.1.4 below about
  core reporting `:denied` no longer applies to apps that port it.

## [0.1.4] - 2026-09-30

### Changed

- **Re-signed with plugin envelope v2** (MOB-287). mob_dev 0.7.2+ verifies
  this signature before evaluating the manifest. mob_dev 0.7.0 / 0.7.1 can't
  read v2 signatures and report this release as `invalid signature` —
  upgrade the host app to `{:mob_dev, "~> 0.7.2", only: :dev, runtime: false}`.

### Fixed

- **Android: `MobLocation.get_once/1` and `start/2` now work under a
  coarse-only grant** (MOB-75). `permissionsFor("location")` requested
  only `ACCESS_FINE_LOCATION`, and the bridge gated on FINE alone.
  Android 12+ shows separate "Precise" and "Approximate" toggles in the
  runtime prompt, so a user who granted Approximate only got
  `{:location, :error, :permission_denied}`. The bridge now requests both
  permissions and treats either grant as sufficient; under coarse-only
  the Fused provider ignores `PRIORITY_HIGH_ACCURACY` and delivers
  balanced accuracy. Note that core's `Mob.Permissions.request/2` still
  reports `{:permission, :location, :denied}` for a coarse-only grant,
  because it requires every requested permission to be granted. Apps
  that gate on that event (as the bundled `DemoScreen` does) won't call
  `get_once/1`/`start/2` in that case.

- **Android: `location_start` no longer leaks the previous LocationCallback**
  (MOB-76). Calling `MobLocation.start/2` twice without an intervening
  `stop/1` (e.g. the user switching accuracy, or the plugin re-activating
  mid-session) overwrote `locationCallback` without ever removing the
  previous one from `FusedLocationProviderClient`. Result: doubled
  location callbacks per fix, doubled battery drain, and no way to stop
  the leaked callback except by restarting the process. `location_start`
  now removes the previous callback before assigning the new one —
  symmetric with `location_stop`'s remove/null pattern.

- **Android: JNI exception no longer leaks onto the BEAM scheduler thread**
  (MOB-77). The zig NIF had zero `ExceptionCheck`/`ExceptionClear` calls,
  and the runtime NIFs didn't guard on a missing bridge cache — a
  `SecurityException` from a missing `ACCESS_FINE_LOCATION`/
  `ACCESS_COARSE_LOCATION` grant, or a `NoSuchMethodError` from an
  older/stripped bridge, would linger on the JNIEnv. The next JNI call on
  the same BEAM scheduler thread was then undefined behaviour per the JNI
  spec, and a null bridge cache passed a null `jclass` into
  `CallStaticVoidMethod` (also UB).

  Fix: introduce a `cacheMethod` helper for `nativeRegister` (same shape as
  the recent mob_bluetooth/mob_background fixes); guard `g_loc_cls == null`
  and `<method> == null` in the runtime NIFs (silent `:ok` — matches the
  moduledoc's documented failure mode where a missing plist key / manifest
  entry silently does nothing); `jni.exceptionClear(jenv)` after both
  `CallStaticVoidMethod` sites (helper `callBridgePidStr` covers
  `get_once` and `start`; `nif_location_stop` calls directly).

  Return-type contracts are unchanged (`MobLocation.get_once/1`,
  `start/2`, `stop/1` all return `socket`). iOS path is untouched.

## [0.1.3] - 2026-06-16

### Changed
- Signed release: the published package now carries a verified Ed25519
  signature (shared mob first-party key, regenerated in CI on every
  release). Generated apps trust it via `config :mob, :trusted_plugins`,
  so it clears the plugin signature gate without `acknowledge_unsafe_plugins`.

## [0.1.2] - 2026-06-15

### Fixed
- Removed a stale `priv/mob_plugin.sig` / `mob_plugin.pub` that shipped in 0.1.1.
  It was signed before the 0.1.1 manifest gained `:screens`, so the signature no
  longer matched the manifest and the plugin signature gate hard-failed
  (`invalid_signature`, not bypassable by `acknowledge_unsafe_plugins`). Now
  unsigned, consistent with the other first-party capability plugins.

## [0.1.1] - 2026-06-15

### Added
- Bundled `MobLocation.DemoScreen` — a ready-to-run sample (get-once / start / stop, live coords) declared in the manifest's `:screens`, so a generated app can kick the tires on activation. It's pure-Elixir and hot-pushable; the plugin is now tier 3 (NIF + screens). Delete the screen + its `:screens` entry in a real app.

## [0.1.0] - 2026-06-12

Initial release. Device location (GPS / network) for Mob apps.

- `MobLocation.start/2` / `stop/1` with updates delivered via `handle_info`.
- Extracted from mob core in the 0.7.0 plugin-extraction wave.
- Requires `mob ~> 0.7`.
