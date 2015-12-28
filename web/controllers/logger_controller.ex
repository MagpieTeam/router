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
    
    case Router.Logger.handle_log(measurements) do
      :ok ->
        json(conn, nil)
      {:error, reason} ->
        conn
        |> Plug.Conn.put_status(500)
        |> json(reason)
    end
  end
end