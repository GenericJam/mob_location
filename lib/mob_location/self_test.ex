defmodule MobLocation.SelfTest do
  @moduledoc """
  The plugin's on-device proof (`Mob.Plugin.SelfTest`), run by
  `mix mob.selftest` and mob_ci for every activated plugin.

  Two native round trips, no UI:

    1. `location_stop/0` must answer `:ok`. It is a no-op while nothing runs,
       but it goes through the NIF into `CLLocationManager` / the Kotlin
       bridge, so the answer proves the native library is linked and
       `nif_init` ran. The host stub's `nif_not_loaded` is a failure.
    2. `location_get_once/0`, then wait for the delivery the native side
       sends back to the caller. A fix (`{:location, %{lat: _, lon: _}}`) or
       `{:location, :error, :unavailable}` both pass: either proves the
       delivery path (the Kotlin `nativeDeliver*` thunks / the Objective-C
       delegate) is wired, and a fix is a feature, not the proof.
       `:permission_denied` is `{:skip, :needs_user}`: the runner pre-grants
       location on emulators and simulators, so that is a phone whose user
       has not answered.

  No answer within 8 s is a skip, not a failure: Android leaves a request
  pending with Play services disabled or the location app-op denied
  (MOB-403), and iOS waits for an undecided permission dialog. The NIF has
  already answered step 1 by then.
  """
  @behaviour Mob.Plugin.SelfTest

  @answer_timeout 8_000

  @impl true
  def run(_ctx) do
    case stop() do
      :ok -> round_trip()
      {:error, reason} -> {:fail, reason}
    end
  end

  defp stop do
    case :mob_location_nif.location_stop() do
      :ok -> :ok
      other -> {:error, "location_stop/0 returned #{inspect(other)}, expected :ok"}
    end
  rescue
    e in ErlangError ->
      {:error, "mob_location_nif is not linked into this build: #{Exception.message(e)}"}
  end

  defp round_trip do
    :ok = :mob_location_nif.location_get_once()

    result =
      receive do
        {:location, %{lat: lat, lon: lon}} when is_float(lat) and is_float(lon) ->
          :pass

        {:location, :error, :unavailable} ->
          # The native side answered through its error path: the delivery is
          # wired, this device just has no fix (no GPS, no Play services).
          :pass

        {:location, :error, :permission_denied} ->
          {:skip, :needs_user}

        {:location, :error, reason} ->
          {:fail, "location_get_once/0 delivered error #{inspect(reason)}, expected :unavailable"}

        {:location, other} ->
          {:fail, "location_get_once/0 delivered #{inspect(other)}, expected %{lat:, lon:}"}
      after
        @answer_timeout ->
          {:skip,
           "location_get_once/0 got no answer in #{div(@answer_timeout, 1000)} s: " <>
             "no fix and the provider left the request pending (MOB-403), " <>
             "or a permission dialog is waiting for the user"}
      end

    # Leave the device as found: a pending request on Android, or an iOS
    # manager still updating after a late fix, is stopped either way.
    :mob_location_nif.location_stop()
    result
  end
end
