defmodule Router.LoggerController do
  use Router.Web, :controller

  def index(conn, _params) do
    conn
    |> assign(:loggers, Magpie.DataAccess.Logger.get())
    |> render("index.html")
  end

  def show(conn, params) do
    {:ok, logger} = Magpie.DataAccess.Logger.get(params["id"])
    sensors = Magpie.DataAccess.Sensor.get(params["id"])
    conn
    |> assign(:logger, logger)
    |> assign(:sensors, sensors)
    |> render("show.html")
  end

  def log(conn, params) do
    measurements = params["measurements"]
    
    case Magpie.DataAccess.Measurement.put(measurements) do
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