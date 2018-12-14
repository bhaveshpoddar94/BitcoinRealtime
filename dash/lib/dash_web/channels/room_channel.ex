defmodule DashWeb.RoomChannel do
  use Phoenix.Channel

  def join("room:bitcoin", _message, socket) do
    {:ok, socket}
  end

  def handle_in("chain", msg, socket) do
    push socket, "chain", msg
    {:noreply, socket}
  end
end