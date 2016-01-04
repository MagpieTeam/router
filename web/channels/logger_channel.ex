defmodule Router.LoggerChannel do
  use Router.Web, :channel

  def join("loggers:" <> logger_id, _message, socket) do
    sensors = Magpie.DataAccess.Sensor.get(logger_id)
    sensors_no = Enum.count(sensors)
    case Router.LoadRegulator.permit?(sensors_no) do
      true ->
        :ok = Router.Presence.register(logger_id, self())
        Enum.each(sensors, fn (s) -> Router.Aggregator.start_link(to_string(s[:id])) end)
        {:ok, socket}
      false ->
        {:error, "request denied by load regulator"}
    end
  end
  
  def handle_in("new_log", msg, socket) do
    measurements = msg["measurements"]

    case Router.Logger.handle_log(measurements) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, reason}, socket}
    end
  end
end