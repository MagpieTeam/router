defmodule Router.PageController do
  use Router.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
