defmodule Router.Presence do
  use GenServer
  require Logger

  alias Phoenix.Socket.Broadcast

  @loggers :loggers
  @nodes :nodes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
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

  def register(logger_id, pid, name) do
    GenServer.call(Router.Presence, {:register, logger_id, pid, name})
  end

  def handle_call({:register, logger_id, pid, name} = msg, _from, %{node: node} = state) do
    Logger.info("Got loggerup #{inspect msg}")

    Process.monitor(pid)
    true = :ets.insert(@loggers, {logger_id, pid, name, node, :online})
    Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_up", %{id: logger_id, name: name, node: node})
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, node, :online]]}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:reply, :ok, state}
  end

  def get_status(logger) do
    case :ets.lookup(@loggers, logger[:id]) do
      [{_id, _pid, _name, node, status}] -> [logger[:id], logger[:name], node, status]
      _ -> [logger[:id], logger[:name], :"", :offline]
    end
  end

  defp connect() do
    Application.get_env(:router, :nodes)
    |> Enum.each(fn(n) -> Node.connect(n) end)
  end

  defp to_port(port) when is_binary(port), do: port
  defp to_port({:system, env_var}), do: to_port(System.get_env(env_var))

  def handle_info({:DOWN, ref, _type, pid, {_info, reason}} = msg, %{node: node} = state) do
    Logger.info("Got local logger :DOWN #{inspect msg}")

    # Potential race condition
    # If this logger has already gone online again, and we have already received that message
    # and thus marked the logger as online, we should not do anything when receiving a :DOWN message.
    # By matching on pid and node we make sure it's actually marked as being online on this node
    # before removing it and before broadcasting it as being offline.
    # Also, we don't know the logger_id, and thus have to use a match!
    case :ets.match(@loggers, {:"$1", pid, :"$2", node, :_}) do
      [] -> 
        {:noreply, state}
      [[logger_id, name]] -> 
        :ets.delete(@loggers, logger_id)
        Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_down", %{id: logger_id, name: name, node: node})
        payload = %{status: [[logger_id, name, "", :offline]]}
        broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: payload}
        Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
        Process.demonitor(ref, [:flush])
        {:noreply, state}
    end
  end

  def handle_info(%Broadcast{event: "logger_up", payload: %{id: logger_id, name: name, node: node}}, state) do
    Logger.info("Got remote logger_up: #{logger_id} on #{node}")

    true = :ets.insert(@loggers, {logger_id, nil, name, node, :online})
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, node, :online]]}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "logger_down", payload: %{id: logger_id, name: name, node: remote_node}}, state) do
    Logger.info("Got remote logger_down: #{logger_id} on #{remote_node}")

    # Potential race condition
    # As in the case of a local logger going :DOWN, this signal could be received 
    # after we have received a message that the logger has gone online on another
    # node. To avoid this, we pin the name of the remote node when we pattern match
    # on the return value from ets.lookup, so it will only match if it is stored in
    # ets as online on the remote node.
    # There is no potential for a race condition if the logger went online again on
    # the node that broadcasted the logger_down message. Erlang guarantees that if process
    # A sends messages X and Y in that order, process B will always receive X before Y. 
    # Thus we will always receive logger_down messages before logger_up messages if 
    # the logger comes online on the same node it disconnected from
    case :ets.lookup(@loggers, logger_id) do
      [{_id, _pid, name, ^remote_node, _status}] ->
        :ets.delete(@loggers, logger_id)
        broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: [[logger_id, name, "", :offline]]}}
        Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
        {:noreply, state}
      [] ->
        {:noreply, state}
    end
  end

  def handle_info({:nodedown, remote_node} = msg, state) do
    Logger.info("Got remote node down: #{remote_node}")

    loggers = :ets.match(@loggers, {:"$1", :_, :"$2", remote_node, :_})
    loggers_unknown = Enum.map(loggers, fn([logger_id, name]) -> {logger_id, nil, name, remote_node, :unknown} end)
    :ets.insert(@loggers, loggers_unknown)
    :ets.delete(@nodes, remote_node)

    status = Enum.map(loggers, fn([logger_id, name]) -> [logger_id, name, node, :unknown] end)

    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: status}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info({:nodeup, remote_node} = msg, %{node: node, endpoint_ip: endpoint_ip} = state) do
    Logger.info("Got remote node up: #{remote_node}")
    # When a new node joins a cluster, all nodes in the cluster receive a :nodeup message
    # from the new node, and the new node receives :nodeup messages from all the other nodes
    # Upon receiving a :nodeup signal from remote_node, each node prepares a list all loggers
    # currently connected to the local node. This list is then sent to the remote node.
    current_loggers = :ets.match(@loggers, {:"$1", :_, :"$2", node, :"$3"})
    GenServer.cast({Router.Presence, remote_node}, {:loggers, current_loggers, node, endpoint_ip})
    {:noreply, state}
  end

  def handle_cast({:loggers, loggers, remote_node, endpoint_ip}, state) do
    Logger.info("Got list of loggers from remote node: #{remote_node}: #{inspect loggers}")

    # Make a list of all the online loggers to insert
    current_loggers = case loggers do
      [] -> []
      loggers ->
        Enum.map(loggers, fn([id, name, status]) ->
          {id, nil, name, remote_node, status} 
        end)
    end
    :ets.insert(@loggers, current_loggers)

    # Delete all those loggers still listed as unknown and return a list to use for new_status message
    offline_loggers = 
      :ets.match(@loggers, {:"$1", :_, :"$2", remote_node, :unknown})
      |> Enum.map(fn([old_logger_id, name], acc) ->
        :ets.delete(@loggers, old_logger_id)
        [old_logger_id, name, "", :offline]
      end)

    status = Enum.reduce(current_loggers, offline_loggers, fn({id, _pid, name, _node, status}, acc) -> 
      [[id, name, remote_node, status] | acc]
    end)
    
    broadcast = %Broadcast{event: "new_status", topic: "loggers:status", payload: %{status: status}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end
end