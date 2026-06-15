defmodule MobLocation.DemoScreen do
  @moduledoc """
  A ready-to-run sample screen exercising `MobLocation`, shipped so a generated
  app can kick the tires the moment the plugin is activated. Declared in the
  plugin manifest's `:screens`, so the host's home can surface it by route
  without writing any code. Delete it (and the manifest entry) in a real app.
  """
  use Mob.Screen

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     Mob.Socket.assign(socket,
       status: "Tap a button to request a location fix",
       lat: nil,
       lon: nil,
       pending: nil
     )}
  end

  @impl true
  def render(assigns) do
    tap_once = {self(), :get_once}
    tap_start = {self(), :start}
    tap_stop = {self(), :stop}

    ~MOB"""
    <Scroll background={:background}>
      <Column background={:background} padding={:space_lg}>
        <Text text="Location" text_size={:lg} text_color={:on_surface} padding={:space_sm} />
        <Text text={assigns.status} text_size={:sm} text_color={:primary} padding={4} />
        <Spacer size={8} />
        <Text text={coord_text(assigns)} text_size={:md} text_color={:on_surface} padding={4} />
        <Spacer size={16} />
        <Button text="Get location once" background={:primary} text_color={:on_primary} padding={:space_md} fill_width={true} on_tap={tap_once} />
        <Spacer size={12} />
        <Button text="Start updates" background={:surface} text_color={:on_surface} padding={:space_md} fill_width={true} on_tap={tap_start} />
        <Spacer size={12} />
        <Button text="Stop updates" background={:surface} text_color={:on_surface} padding={:space_md} fill_width={true} on_tap={tap_stop} />
      </Column>
    </Scroll>
    """
  end

  defp coord_text(%{lat: nil}), do: "No fix yet"
  defp coord_text(%{lat: lat, lon: lon}), do: "#{lat}, #{lon}"

  @impl true
  def handle_info({:tap, :get_once}, socket) do
    {:noreply,
     socket
     |> Mob.Permissions.request(:location)
     |> Mob.Socket.assign(pending: :get_once, status: "Requesting location permission…")}
  end

  def handle_info({:tap, :start}, socket) do
    {:noreply,
     socket
     |> Mob.Permissions.request(:location)
     |> Mob.Socket.assign(pending: :start, status: "Requesting location permission…")}
  end

  def handle_info({:tap, :stop}, socket) do
    {:noreply, MobLocation.stop(socket) |> Mob.Socket.assign(status: "Stopped", pending: nil)}
  end

  def handle_info({:permission, :location, :granted}, socket) do
    socket =
      case socket.assigns.pending do
        :get_once -> MobLocation.get_once(socket)
        :start -> MobLocation.start(socket)
        _ -> socket
      end

    {:noreply,
     Mob.Socket.assign(socket, status: "Permission granted — waiting for a fix…", pending: nil)}
  end

  def handle_info({:permission, :location, :denied}, socket) do
    {:noreply, Mob.Socket.assign(socket, status: "Location permission denied", pending: nil)}
  end

  def handle_info({:location, %{lat: lat, lon: lon}}, socket) do
    {:noreply, Mob.Socket.assign(socket, lat: lat, lon: lon, status: "Got a fix")}
  end

  def handle_info({:location, :error, reason}, socket) do
    {:noreply, Mob.Socket.assign(socket, status: "Location error: #{inspect(reason)}")}
  end
end
