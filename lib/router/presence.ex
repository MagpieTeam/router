defmodule Router.Presence do
  use GenServer

  alias Phoenix.Socket.Broadcast

  @table :presence

  def start_link(opts \\ []) do
    # pass in the name of the local server
    # connect to other nodes by hand
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def register(logger_id, pid) do
    GenServer.call(Router.Presence, {:register, logger_id, pid})
  end

  def connect() do
    # TODO: connect to nodes specified in config
    # except your own node name
    [:"n1@euron", :"n2@euron", :"n3@euron"]
    |> Enum.each(fn(n) -> Node.connect(n) end)
  end

  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :protected])

    Phoenix.PubSub.subscribe(Router.PubSub, self(), "presence:gossip") # TODO: handle logger broadcasts - put in state
    :ok = :net_kernel.monitor_nodes(true)
    # TODO: join the cluster here?
    {:ok, %{node: Node.self()}}
  end

  def handle_call({:register, logger_id, pid} = msg, _from, %{node: node} = state) do
    IO.puts("Got loggerup #{inspect msg}")
    Process.monitor(pid)
    true = :ets.insert(@table, {logger_id, pid, node, :online})
    # broadcast on gossip and local
    Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_up", %{id: logger_id, node: node})
    broadcast = %Broadcast{event: "logger_up", topic: "loggers:status", payload: %{id: logger_id, node: node}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, _type, pid, {_info, reason}} = msg, %{node: node} = state) do
    # logger down, remove
    IO.puts("Got :DOWN #{inspect msg}")
    # TODO: If ets returns nil, this is gonna crash. Please fix
    case :ets.match(@table, {:"$1", pid, node, :_}) |> List.first |> List.first do
      nil -> 
        {:noreply, state}
      logger_id -> 
        :ets.delete(@table, logger_id)
        # broadcast on gossip and local
        Router.Endpoint.broadcast_from(self(), "presence:gossip", "logger_down", %{id: logger_id, node: node})
        broadcast = %Broadcast{event: "logger_down", topic: "loggers:status", payload: %{id: logger_id, node: node}}
        Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
        Process.demonitor(ref, [:flush])
        {:noreply, state}
    end
  end

  def handle_info(%Broadcast{event: "logger_up", payload: %{id: logger_id, node: node}}, state) do
    IO.puts("Got remote logger_up: #{logger_id} on #{node}")

    true = :ets.insert(@table, {logger_id, nil, node, :online})
    broadcast = %Broadcast{event: "logger_up", topic: "loggers:status", payload: %{id: logger_id, node: node}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "logger_down", payload: %{id: logger_id, node: node}}, state) do
    IO.puts("Got remote logger_down: #{logger_id} on #{node}")

    :ets.delete(@table, logger_id)
    broadcast = %Broadcast{event: "logger_down", topic: "loggers:status", payload: %{id: logger_id, node: node}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_info({:nodeup, remote_node} = msg, %{node: node} = state) do
    IO.puts("Got remote node up: #{remote_node}")
    # This will happen both on the node that was offline
    # and the node that is online. Send a message to the node with current loggers
    loggers = :ets.match(@table, {:"$1", :_, node, :"$2"})
    GenServer.cast({Router.Presence, remote_node}, {:loggers, loggers, node})
    {:noreply, state}
  end

  def handle_info({:nodedown, node} = msg, state) do
    IO.puts("Got remote node down: #{node}")

    logger_ids = :ets.match(@table, {:"$1", :_, node, :online})
    loggers = Enum.map(logger_ids, fn([ l | _]) -> {l, nil, node, :unknown} end)
    :ets.insert(@table, loggers)

    broadcast = %Broadcast{event: "loggers_unknown", topic: "loggers:status", payload: %{loggers: logger_ids}}
    Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
    {:noreply, state}
  end

  def handle_cast({:loggers, loggers, remote_node}, %{node: node} = state) do
    IO.puts("Got list of loggers from remote node: #{remote_node}: #{inspect loggers}")

    # delete all for this node, then insert the new ones
    # the genserver serialises all updates, thus, if a logger comes online on another node
    # it will either get that message before this one, or after, and both cases
    # will be handled gracefully
    old_loggers = :ets.match(@table, {:"$1", :_, remote_node, :_})
    Enum.each(old_loggers, fn([ l | _]) -> 
      :ets.delete(@table, l)
    end)

    # create list of online loggers for insertion
    case loggers do
      [] ->
        {:noreply, state}
      loggers ->
        new_loggers = Enum.map(loggers, fn(l) -> 
          [id | tail] = l
          [status | _] = tail
          {id, nil, remote_node, status} 
        end)
        :ets.insert(@table, new_loggers)
        
        broadcast = %Broadcast{event: "node_up", topic: "loggers:status", payload: nil}
        Phoenix.PubSub.Local.broadcast(Router.PubSub.Local, self(), "loggers:status", broadcast)
        {:noreply, state}
    end  
  end
end