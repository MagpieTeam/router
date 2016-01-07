defmodule Router.LoggerChannel do
  use Router.Web, :channel

  def join("loggers:status", _message, socket) do
    send(self(), :status_join)

    {:ok, socket}
  end

  def handle_info(:status_join, socket) do
    loggers = Magpie.DataAccess.Logger.get()
    status = Enum.map(loggers, fn(l) ->
      Router.Presence.get_status(l[:id])
    end)
    # IO.puts(status)
    push(socket, "new_status", %{status: status})

    {:noreply, socket}
  end

  def join("loggers:" <> logger_id, _message, socket) do
    {:ok, logger} = Magpie.DataAccess.Logger.get(logger_id)
    sensors = Magpie.DataAccess.Sensor.get(logger_id)
    sensors_no = Enum.count(sensors)
    case Router.LoadRegulator.permit?(sensors_no) do
      true ->
        :ok = Router.Presence.register(logger_id, self(), logger[:name])
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