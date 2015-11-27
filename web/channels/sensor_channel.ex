defmodule Router.SensorChannel do
  use Router.Web, :channel

  def join("sensors:" <> _sensor_id, _message, socket) do
    {:ok, socket}
  end

end