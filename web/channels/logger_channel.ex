defmodule Router.LoggerChannel do
  use Router.Web, :channel

  def join("loggers:" <> _logger_id, _message, socket) do
    {:ok, socket}
  end
  
  def handle_in("new_log", msg, socket) do
    measurements = msg["measurements"]

    case Router.DataAccess.Measurement.put(measurements) do
     {:ok, measurements} ->
       broadcast_measurements(measurements)
       {:reply, :ok, socket}
     {:error, reason} ->
       {:reply, {:error, reason}, socket}
    end
  end

  defp broadcast_measurements(measurements) do
    Enum.each(measurements, fn (m) -> 
      Router.Endpoint.broadcast("sensors:" <> m["sensor_id"], "new_log", 
        %{sensor_id: m["sensor_id"], timestamp: m["timestamp"], value: m["value"], metadata: m["metadata"]})
      end 
    )
  end

end