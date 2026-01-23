defmodule MyAppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # PubSub Metrics
      counter("phoenix.channel.join.count",
        tags: [:channel]
      ),
      counter("phoenix.channel.leave.count",
        tags: [:channel]
      ),
      last_value("my_app.cluster.node_count",
        description: "Number of connected nodes in cluster"
      ),
      counter("my_app.pubsub.broadcast.count",
        tags: [:topic],
        description: "Number of PubSub broadcasts"
      ),
      counter("my_app.pubsub.broadcast.error",
        tags: [:topic],
        description: "Failed PubSub broadcasts"
      ),
      # GraphQL Subscription metrics
      counter("absinthe.subscription.publish.count",
        tags: [:subscription],
        description: "GraphQL subscription publishes"
      ),

      # OpenAI Streaming Speed Metrics
      # Time to First Chunk (OpenAI processing time)
      summary("my_app.openai.time_to_first_chunk.duration",
        unit: {:native, :millisecond},
        description: "Time until first chunk arrives (OpenAI processing)",
        tags: [:thread_id]
      ),
      # Chunk Interval (actual streaming speed)
      summary("my_app.openai.chunk.interval",
        unit: {:native, :millisecond},
        description: "Time between OpenAI chunks (streaming speed)",
        tags: [:thread_id]
      ),
      # Broadcast time
      summary("my_app.openai.chunk.duration",
        unit: {:native, :millisecond},
        description: "Time to broadcast each chunk",
        tags: [:thread_id, :type]
      ),
      summary("my_app.openai.stream.completed.duration",
        unit: {:native, :millisecond},
        description: "Total time for complete stream",
        tags: [:thread_id]
      ),

      # Message broadcast metrics
      summary("my_app.message.completed.duration",
        unit: {:native, :millisecond},
        description: "Time to broadcast completed message",
        tags: [:thread_id, :type]
      ),

      # PubSub broadcast metrics
      summary("my_app.pubsub.broadcast.duration",
        unit: {:native, :millisecond},
        description: "Time for PubSub broadcast",
        tags: [:topic, :event]
      ),
      counter("my_app.pubsub.broadcast.count",
        tags: [:topic, :event],
        description: "Number of PubSub broadcasts"
      ),

      # Database Metrics
      # summary("my_app.repo.query.total_time",
      #   unit: {:native, :millisecond},
      #   description: "The sum of the other measurements"
      # ),
      # summary("my_app.repo.query.decode_time",
      #   unit: {:native, :millisecond},
      #   description: "The time spent decoding the data received from the database"
      # ),
      # summary("my_app.repo.query.query_time",
      #   unit: {:native, :millisecond},
      #   description: "The time spent executing the query"
      # ),
      # summary("my_app.repo.query.queue_time",
      #   unit: {:native, :millisecond},
      #   description: "The time spent waiting for a database connection"
      # ),
      # summary("my_app.repo.query.idle_time",
      #   unit: {:native, :millisecond},
      #   description:
      #     "The time the connection spent waiting before being checked out for the query"
      # ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {MyAppWeb, :count_users, []}
      {__MODULE__, :dispatch_cluster_info, []},
      {__MODULE__, :dispatch_pubsub_info, []}
    ]
  end

  # Custom measurement for cluster info
  def dispatch_cluster_info do
    nodes = [Node.self() | Node.list()]
    :telemetry.execute([:my_app, :cluster], %{node_count: length(nodes)}, %{})
  end

  def dispatch_pubsub_info do
    # Count active PubSub subscribers
    :telemetry.execute([:my_app, :pubsub], %{}, %{})
  end
end
