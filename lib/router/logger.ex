defmodule Router.Logger do
  def handle_log(measurements) do
    case Magpie.DataAccess.Measurement.put(measurements) do
      {:ok, measurements} ->
        broadcast_measurements(measurements)
        :ok
      {:error, reason} ->
        {:error, reason}
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