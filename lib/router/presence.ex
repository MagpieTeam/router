defmodule Router.Presence do
  use GenServer
  require Logger

  alias Phoenix.Socket.Broadcast

  @loggers :loggers
  @nodes :nodes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def register(logger_id, pid, name) do
    GenServer.call(Router.Presence, {:register, logger_id, pid, name})
  end

  def get_status(logger) do
    case :ets.match(@loggers, {logger[:id], :_, :"$1", :"$2"}) do
      [[node, status]] -> [logger[:id], logger[:name], node, status]
      _ -> [logger[:id], logger[:name], :"", :offline]
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

  def handle_call({:register, logger_id, pid, name} = msg, _from, %{node: node} = state) do
    Logger.debug("Got loggerup #{inspect msg}")
    Process.monitor(pid)
    true = :ets.insert(@loggers, {logger_id, pid, name, node, :online})
    # broadcast on gossip and local
    Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_up", %{id: logger_id, name: name, node: node})
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, node, :online]]}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, _type, pid, {_info, reason}} = msg, %{node: node} = state) do
    # logger down, remove
    Logger.debug("Got :DOWN #{inspect msg}")
    # TODO: If ets returns nil, this is gonna crash. Please fix
    case :ets.match(@loggers, {:"$1", pid, :"$2", node, :_}) do
      nil -> 
        {:noreply, state}
      [[logger_id, name]] -> 
        :ets.delete(@loggers, logger_id)
        # broadcast on gossip and local
        Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_down", %{id: logger_id, name: name, node: node})
        broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, "", :offline]]}}
        Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
        Process.demonitor(ref, [:flush])
        {:noreply, state}
    end
  end

  def handle_info(%Broadcast{event: "logger_up", payload: %{id: logger_id, name: name, node: node}}, state) do
    Logger.debug("Got remote logger_up: #{logger_id} on #{node}")

    true = :ets.insert(@loggers, {logger_id, nil, name, node, :online})
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, node, :online]]}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "logger_down", payload: %{id: logger_id, name: name, node: node}}, state) do
    Logger.debug("Got remote logger_down: #{logger_id} on #{node}")

    :ets.delete(@loggers, logger_id)
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, "", :offline]]}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info({:nodeup, remote_node} = msg, %{node: node, endpoint_ip: endpoint_ip} = state) do
    Logger.debug("Got remote node up: #{remote_node}")
    # When two nodes connect, both receive this message
    # Each node sends a list to the remote node containing
    # a list of loggers on the local node
    loggers = :ets.match(@loggers, {:"$1", :_, :"$2", node, :"$3"})
    GenServer.cast({Router.Presence, remote_node}, {:current_loggers, loggers, node, endpoint_ip})
    {:noreply, state}
  end

  def handle_info({:nodedown, node} = msg, state) do
    Logger.debug("Got remote node down: #{node}")

    logger_ids = :ets.match(@loggers, {:"$1", :_, :"$2", node, :_})
    loggers = Enum.map(logger_ids, fn([logger_id, name]) -> {logger_id, nil, name, node, :unknown} end)
    :ets.insert(@loggers, loggers)
    :ets.delete(@nodes, node)

    status = Enum.map(logger_ids, fn([logger_id, name]) -> [logger_id, name, node, :unknown] end)

    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: status}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_cast({:current_loggers, loggers, remote_node, endpoint_ip}, state) do
    Logger.debug("Got list of loggers from remote node: #{remote_node}: #{inspect loggers}")
    
    # delete all loggers for this node in ets if they are not in the new list of loggers,
    # and accumulate them in offline_loggers for new_status broadcast
    offline_loggers = 
      :ets.match(@loggers, {:"$1", :_, :"$2", remote_node, :_})
      |> IO.inspect()
      |> Enum.reduce([], fn ([old_logger_id, name], acc) ->
        contains_old_logger? = fn([new_logger_id, _name, _status]) -> 
          old_logger_id == new_logger_id
        end
        case Enum.find(loggers, contains_old_logger?) do
          nil ->
            :ets.delete(@loggers, old_logger_id)
            [[old_logger_id, name, "", :offline] | acc]
          _ -> acc 
        end
      end)

    # create list of online loggers for insertion
    new_loggers = case loggers do
      [] -> []
      loggers ->
        Enum.map(loggers, fn([id, name, status]) ->
          {id, nil, name, remote_node, status} 
        end)
    end
    :ets.insert(@loggers, new_loggers)
    :ets.insert(@nodes, {remote_node, endpoint_ip})

    status = Enum.reduce(new_loggers, offline_loggers, fn({id, _, name, _, status}, acc) -> 
      [[id, name, remote_node, status] | acc]
    end)
    
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: status}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end
end