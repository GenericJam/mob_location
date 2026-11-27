defmodule MobLocation.SelfTest do
  @moduledoc """
  The plugin's on-device proof (`Mob.Plugin.SelfTest`), run by
  `mix mob.selftest` and mob_ci for every activated plugin.

  One native round trip, no UI: `location_get_once/0`, then wait for what
  the native side sends back to the caller.

    * A fix (`{:location, %{lat: _, lon: _, speed: _, course: _, time: _}}`)
      or `{:location, :error, :unavailable}` pass: either proves the NIF is
      linked, the Kotlin bridge / Objective-C delegate is registered and the
      delivery path (the `nativeDeliver*` thunks / the delegate) is wired. A
      fix is a feature, not the proof.
    * A fix without `speed`, `course` and `time`, or with one of the wrong
      type, is a failure: the native side and this module ship in one
      package, so the old four-key shape means a stale or mismatched native
      build.
    * `{:error, :bridge_not_registered}` from the NIF (Android: the
      bootstrap never called `MobLocationBridge.register()`, or a method-ID
      lookup failed) and `{:location, :error, :no_activity}` (the bootstrap
      never handed the bridge an Activity) are failures: the plugin can
      never answer in that host.
    * `:permission_denied` is `{:skip, :needs_user}`: the runner pre-grants
      location on emulators and simulators, so that is a device whose user
      has not answered.
    * No answer within 8 s is a skip: Android leaves a request pending with
      Play services disabled or the location app-op denied (MOB-403); on
      iOS an undecided permission prompt (which this call raises on a
      physical iPhone, and leaves for the user) waits for the user.

  The host stub's `nif_not_loaded` is a failure. The test calls
  `location_stop/0` afterwards only on iOS, where a failed one-shot request
  leaves the shared manager updating; on Android a pending request is not
  cancellable and `location_stop/0` would remove the host app's own
  subscription instead.
  """
  @behaviour Mob.Plugin.SelfTest

  @answer_timeout 8_000

  @impl true
  def run(%{platform: platform}) do
    case :mob_location_nif.location_get_once() do
      :ok ->
        result = await_answer(@answer_timeout, platform)
        if platform == :ios, do: :mob_location_nif.location_stop()
        result

      {:error, :bridge_not_registered} ->
        {:fail,
         "Kotlin MobLocationBridge not registered (nativeRegister never ran or a method-ID lookup failed)"}

      other ->
        {:fail, "location_get_once/0 returned #{inspect(other)}, expected :ok"}
    end
  rescue
    e in ErlangError ->
      {:fail, "mob_location_nif is not linked into this build: #{Exception.message(e)}"}
  end

  @doc false
  # The classification of what the native side delivers after get_once.
  @spec await_answer(non_neg_integer(), :ios | :android) :: Mob.Plugin.SelfTest.result()
  def await_answer(timeout, platform) do
    receive do
      {:location, %{lat: lat, lon: lon} = fix} when is_float(lat) and is_float(lon) ->
        check_fix_shape(fix)

      {:location, :error, :unavailable} ->
        :pass

      {:location, :error, :no_activity} ->
        {:fail, "MobLocationBridge has no Activity (MobActivityAware.setActivity never called)"}

      {:location, :error, :permission_denied} ->
        {:skip, :needs_user}

      {:location, :error, reason} ->
        {:fail, "location_get_once/0 delivered error #{inspect(reason)}, expected :unavailable"}

      {:location, other} ->
        {:fail, "location_get_once/0 delivered #{inspect(other)}, expected %{lat:, lon:}"}
    after
      timeout ->
        case platform do
          :ios ->
            {:skip, :needs_user}

          :android ->
            {:skip,
             "location_get_once/0 got no answer in #{div(timeout, 1000)} s: " <>
               "no fix and the provider left the request pending (MOB-403)"}
        end
    end
  end

  # speed and course are nil when the platform has none; time is always there.
  defp check_fix_shape(fix) do
    cond do
      not Enum.all?([:speed, :course, :time], &Map.has_key?(fix, &1)) ->
        {:fail,
         "fix #{inspect(fix)} has no speed/course/time: the native side predates them " <>
           "(stale or mismatched native build)"}

      not (is_nil(fix.speed) or is_number(fix.speed)) or
        not (is_nil(fix.course) or is_number(fix.course)) or not is_integer(fix.time) ->
        {:fail,
         "fix #{inspect(fix)}: expected speed and course as a number or nil, time as integer ms"}

      true ->
        :pass
    end
  end
end
