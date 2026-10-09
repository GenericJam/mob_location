defmodule MobLocation do
  @moduledoc """
  Device location (GPS / network) — a Mob plugin (extracted from mob core in
  Wave 2).

  Requires `:location` permission (request via `Mob.Permissions.request/2`;
  this plugin registers the `:location` capability with the platform permission
  registry). iOS additionally needs `NSLocationWhenInUseUsageDescription` in
  `Info.plist`; Android needs `ACCESS_FINE_LOCATION` and/or
  `ACCESS_COARSE_LOCATION` — both merged from this plugin's manifest at build
  time. A missing plist key / manifest entry is the single most common reason
  this module silently does nothing.

  Location updates arrive as:

      handle_info({:location, %{lat: lat, lon: lon, accuracy: acc, altitude: alt}}, socket)
      handle_info({:location, :error, reason}, socket)

  Common `reason` atoms:

    * `:permission_denied` — user denied `:location` (or revoked it mid-session).
    * `:unavailable` — the OS can't get a fix right now.
    * `:no_activity` — Android only: the plugin bootstrap never gave the bridge
      an Activity (a host integration bug, caught by the self-test).

  iOS: `CLLocationManager`. Android: `FusedLocationProviderClient`.
  """

  @type accuracy :: :high | :balanced | :low

  @doc "Request a single location fix, then stop."
  @spec get_once(Mob.Socket.t()) :: Mob.Socket.t()
  def get_once(socket) do
    :mob_location_nif.location_get_once()
    socket
  end

  @doc """
  Start continuous location updates.

  Options:
    - `accuracy: :high | :balanced | :low` (default `:balanced`)

  Call `stop/1` when done to save battery.
  """
  @spec start(Mob.Socket.t(), keyword()) :: Mob.Socket.t()
  def start(socket, opts \\ []) do
    accuracy = Keyword.get(opts, :accuracy, :balanced)
    :mob_location_nif.location_start(accuracy)
    socket
  end

  @doc "Stop continuous location updates."
  @spec stop(Mob.Socket.t()) :: Mob.Socket.t()
  def stop(socket) do
    :mob_location_nif.location_stop()
    socket
  end
end
