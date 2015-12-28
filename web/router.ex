defmodule Router.Router do
  use Router.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Router do
    pipe_through :browser # Use the default browser stack

    get "/loggers", LoggerController, :index
    get "/loggers/:id", LoggerController, :show
  end

  # Other scopes may use custom stacks.
  scope "/api", Router do
    pipe_through :api
    get("/nodes", NodeController, :index)

    post("/start", LoggerController, :start)
    post("/stop", LoggerController, :stop)
    post("/log", LoggerController, :log)
  end
end
