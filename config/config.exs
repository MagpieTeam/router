# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :router, Router.Endpoint,
  url: [host: System.get_env("IP")],
  root: Path.dirname(__DIR__),
  secret_key_base: "MvqGIleGGtQ5AIW3yM4jGeTZkjHH/tZGZKNwTsKZoRI79nKqHkF0dwAxopu3qXc/",
  render_errors: [accepts: ~w(html json)],
  pubsub: [name: Router.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"

# Configure phoenix generators
config :phoenix, :generators,
  migration: true,
  binary_id: false
  