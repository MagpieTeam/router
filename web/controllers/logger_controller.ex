defmodule Router.LoggerController do
  use Router.Web, :controller

  def log(conn, params) do
    # Expected format: 
    # { measurements: [
    #     {
    #       'sensor_id': 'uuid',
    #       'timestamp': 'milliseconds since epoch',
    #       'value': 'variable precision decimal',
    #       'metadata': 'bytes as string'
    #     }
    #   ]
    # }
    measurements = params["measurements"]
    case Router.DataAccess.Measurements.put(measurements) do
      {:ok, measurements} -> 
        broadcast_measurements(measurements)
        json(conn, nil)
      {:error, reason} ->
        conn
        |> Plug.Conn.put_status(500)
        |> json(reason)
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