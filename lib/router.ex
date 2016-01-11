defmodule Router do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Start the endpoint when the application starts
      supervisor(Router.Endpoint, []),
      worker(Router.Presence, [[name: Router.Presence]]),
      worker(Router.LoadRegulator, [[name: Router.LoadRegulator]])
    ]

    opts = [strategy: :one_for_one, name: Router.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Router.Endpoint.config_change(changed, removed)
    :ok
  end
end
