%{
  name: :mob_location,
  mob_version: "~> 0.6",
  plugin_spec_version: 1,
  description: "Device location (GPS/network) — extracted from mob core in Wave 2",
  # A sample screen the host can navigate to by route (auto-listed by a home
  # that enumerates Mob.Plugins.screens/0). Pure-Elixir + hot-pushable; drop it
  # and this entry in a real app that builds its own UI.
  screens: [
    %{module: MobLocation.DemoScreen, default_route: "/mob_location/demo"}
  ],
  nifs: [
    # iOS: Objective-C NIF driving CLLocationManager. lang: :objc -> compiled as
    # ObjC (.m) with -fobjc-arc; platform: :ios so it isn't pulled into the
    # Android build.
    %{module: :mob_location_nif, native_dir: "priv/native/ios", lang: :objc, platform: :ios},
    # Android: zig NIF bridging to FusedLocationProviderClient via the Kotlin
    # MobLocationBridge. platform: :android so the iOS build skips it.
    %{module: :mob_location_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  permissions: [
    # iOS handler self-registered at NIF load (mob_location_request_permission);
    # Android mapping supplied by MobLocationBridge implementing
    # MobPermissionProvider (auto-discovered at bootstrap).
    %{capability: :location, ios: %{handler: "mob_location_request_permission"}}
  ],
  android: %{
    bridge_kt: "priv/native/android/MobLocationBridge.kt",
    bridge_class: "io.mob.location.MobLocationBridge",
    permissions: [
      "android.permission.ACCESS_FINE_LOCATION",
      "android.permission.ACCESS_COARSE_LOCATION"
    ],
    gradle_deps: ["com.google.android.gms:play-services-location:21.0.1"]
  },
  ios: %{
    frameworks: ["CoreLocation"],
    plist_keys: %{
      "NSLocationWhenInUseUsageDescription" =>
        "Location is used to provide location-based features."
    }
  }
}
