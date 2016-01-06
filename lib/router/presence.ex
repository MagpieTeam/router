defmodule Router.Presence do
  use GenServer
  require Logger

  alias Phoenix.Socket.Broadcast

  @loggers :loggers
  @nodes :nodes

  def start_link(opts \\ []) do
    # pass in the name of the local server
    # connect to other nodes by hand
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def register(logger_id, pid) do
    GenServer.call(Router.Presence, {:register, logger_id, pid})
  end

  def get_status(logger_id) do
    case :ets.match(@loggers, {logger_id, :_, :"$2", :"$3"}) do
      [[ node, status ]] -> [logger_id, node, status]
      _ -> [logger_id, :"", :offline]
    end
  end

  def connect() do
    # TODO: connect to nodes specified in config
    # except your own node name
    Application.get_env(:router, :nodes)
    |> Enum.each(fn(n) -> Node.connect(n) end)
  end

  def init(:ok) do
    :ets.new(@loggers, [:named_table, :set, :protected])
    :ets.new(@nodes, [:named_table, :set, :protected])

    :ok = :net_kernel.monitor_nodes(true)
    :ok = connect()
    Router.Endpoint.subscribe(self(), "presence:gossip")

    node = Node.self()
    ip = Router.Endpoint.config(:url)[:host]
    port_conf = Router.Endpoint.config(:http)[:port]
    port = to_port(port_conf)
    endpoint_ip = "#{ip}:#{port}"
    :ets.insert(@nodes, {node, endpoint_ip})

    {:ok, %{node: node, endpoint_ip: endpoint_ip}}
  end

  defp to_port(port) when is_binary(port), do: port
  defp to_port({:system, env_var}), do: to_port(System.get_env(env_var))

  def handle_call({:register, logger_id, pid} = msg, _from, %{node: node} = state) do
    Logger.debug("Got loggerup #{inspect msg}")
    Process.monitor(pid)
    true = :ets.insert(@loggers, {logger_id, pid, node, :online})
    # broadcast on gossip and local
    Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_up", %{id: logger_id, node: node})
    broadcast = %Broadcast{event: "logger_up", topic: "loggers:status", payload: %{id: logger_id, node: node}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, _type, pid, {_info, reason}} = msg, %{node: node} = state) do
    # logger down, remove
    Logger.debug("Got :DOWN #{inspect msg}")
    # TODO: If ets returns nil, this is gonna crash. Please fix
    case :ets.match(@loggers, {:"$1", pid, node, :_}) |> List.first |> List.first do
      nil -> 
        {:noreply, state}
      logger_id -> 
        :ets.delete(@loggers, logger_id)
        # broadcast on gossip and local
        Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_down", %{id: logger_id, node: node})
        broadcast = %Broadcast{event: "logger_down", topic: "loggers:status", payload: %{id: logger_id, node: node}}
        Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
        Process.demonitor(ref, [:flush])
        {:noreply, state}
    end
  end

  def handle_info(%Broadcast{event: "logger_up", payload: %{id: logger_id, node: node}}, state) do
    Logger.debug("Got remote logger_up: #{logger_id} on #{node}")

    true = :ets.insert(@loggers, {logger_id, nil, node, :online})
    broadcast = %Broadcast{event: "logger_up", topic: "loggers:status", payload: %{id: logger_id, node: node}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "logger_down", payload: %{id: logger_id, node: node}}, state) do
    Logger.debug("Got remote logger_down: #{logger_id} on #{node}")

    :ets.delete(@loggers, logger_id)
    broadcast = %Broadcast{event: "logger_down", topic: "loggers:status", payload: %{id: logger_id, node: node}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info({:nodeup, remote_node} = msg, %{node: node, endpoint_ip: endpoint_ip} = state) do
    Logger.debug("Got remote node up: #{remote_node}")
    # When two nodes connect, both receive this message
    # Each node sends a list to the remote node containing
    # a list of loggers on the local node
    loggers = :ets.match(@loggers, {:"$1", :_, node, :"$2"})
    GenServer.cast({Router.Presence, remote_node}, {:loggers, loggers, node, endpoint_ip})
    {:noreply, state}
  end

  def handle_info({:nodedown, node} = msg, state) do
    Logger.debug("Got remote node down: #{node}")

    logger_ids = :ets.match(@loggers, {:"$1", :_, node, :online})
    loggers = Enum.map(logger_ids, fn([ l | _]) -> {l, nil, node, :unknown} end)
    :ets.insert(@loggers, loggers)
    :ets.delete(@nodes, node)

    broadcast = %Broadcast{event: "loggers_unknown", topic: "loggers:status", payload: %{loggers: logger_ids}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_cast({:loggers, loggers, remote_node, endpoint_ip}, %{node: node} = state) do
    Logger.debug("Got list of loggers from remote node: #{remote_node}: #{inspect loggers}")

    # delete all for this node, then insert the new ones
    # the genserver serialises all updates, thus, if a logger comes online on another node
    # it will either get that message before this one, or after, and both cases
    # will be handled gracefully
    old_loggers = :ets.match(@loggers, {:"$1", :_, remote_node, :_})
    Enum.each(old_loggers, fn([ logger | _]) ->
      :ets.delete(@loggers, logger)
    end)

    # create list of online loggers for insertion
    new_loggers = case loggers do
      [] -> []
      loggers ->
        Enum.map(loggers, fn(logger) ->
          [id | [ status | _tail ] ] = logger
          {id, nil, remote_node, status} 
        end)
    end

    :ets.insert(@loggers, new_loggers)
    :ets.insert(@nodes, {remote_node, endpoint_ip})
    broadcast = %Broadcast{event: "node_up", topic: "loggers:status", payload: nil}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end
end