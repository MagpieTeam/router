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

  def start(conn, params) do
    logger_id = params["logger_id"]
    {:ok, logger_pid} = Router.HttpLogger.start(logger_id)
    token = Phoenix.Token.sign(Router.Endpoint, "logger", logger_pid)
    json(conn, %{token: token})
  end

  def stop(conn, params) do
    token = params["token"]
    {:ok, logger_pid} = Phoenix.Token.verify(Router.Endpoint, "logger", token)
    Router.HttpLogger.stop(logger_pid)
    json(conn, nil)
  end

  def log(conn, params) do
    measurements = params["measurements"]
    token = params["token"]
    case Phoenix.Token.verify(Router.Endpoint, "logger", token) do
      {:ok, logger_pid} ->
        case Router.HttpLogger.log(logger_pid, measurements) do
          :ok ->
            json(conn, nil)
          {:error, reason} ->
            conn
            |> Plug.Conn.put_status(500)
            |> json(reason)
        end
      {:error, :invalid} ->
        conn
        |> Plug.Conn.put_status(400)
        |> json("invalid token")
    end    
  end
end