defmodule MyAppWeb.StreamSpeedLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(1000, self(), :update)
      attach_telemetry()
    end

    {:ok,
     assign(socket,
       nodes: get_cluster_nodes(),
       avg_chunk_interval: 0.0,
       avg_time_to_first_chunk: 0.0,
       avg_broadcast_time: 0.0,
       chunks_per_second: 0.0,
       total_chunks: 0,
       last_update: System.monotonic_time(),
       chunk_count: 0,
       samples: [],
       ttfc_samples: [],
       performance_status: "idle"
     )}
  end

  def handle_info(
        {:telemetry, [:my_app, :openai, :time_to_first_chunk], measurements, _metadata},
        socket
      ) do
    ttfc_ms =
      (measurements[:duration] || 0)
      |> then(&System.convert_time_unit(&1, :native, :millisecond))
      |> then(&(&1 * 1.0))

    # Keep last 10 TTFC samples
    new_ttfc_samples = [ttfc_ms | Enum.take(socket.assigns.ttfc_samples, 9)]

    avg_ttfc =
      if length(new_ttfc_samples) > 0 do
        Enum.sum(new_ttfc_samples) / length(new_ttfc_samples)
      else
        0.0
      end

    {:noreply,
     socket
     |> assign(avg_time_to_first_chunk: Float.round(avg_ttfc, 1))
     |> assign(ttfc_samples: new_ttfc_samples)}
  end

  # Handle the :update timer message
  def handle_info(:update, socket) do
    current_time = System.monotonic_time()

    time_diff =
      System.convert_time_unit(
        current_time - socket.assigns.last_update,
        :native,
        :second
      )

    chunks_per_second =
      if time_diff > 0 do
        socket.assigns.chunk_count / time_diff
      else
        0.0
      end

    status =
      cond do
        chunks_per_second > 10 -> "streaming"
        chunks_per_second > 0 -> "active"
        true -> "idle"
      end

    {:noreply,
     socket
     |> assign(chunks_per_second: Float.round(chunks_per_second, 1))
     |> assign(last_update: current_time)
     |> assign(chunk_count: 0)
     |> assign(performance_status: status)
     |> assign(nodes: get_cluster_nodes())}
  end

  # Handle telemetry events
  def handle_info({:telemetry, [:my_app, :openai, :chunk], measurements, _metadata}, socket) do
    # Convert to milliseconds and ensure we get floats
    interval_ms =
      (measurements[:interval] || 0)
      |> then(&System.convert_time_unit(&1, :native, :millisecond))
      |> then(&(&1 * 1.0))

    duration_ms =
      (measurements[:duration] || 0)
      |> then(&System.convert_time_unit(&1, :native, :millisecond))
      |> then(&(&1 * 1.0))

    # Keep last 100 samples for average
    new_interval_samples = [interval_ms | Enum.take(socket.assigns.samples, 99)]

    avg_interval =
      if length(new_interval_samples) > 0 do
        Enum.sum(new_interval_samples) / length(new_interval_samples)
      else
        0.0
      end

    {:noreply,
     socket
     |> assign(chunk_count: socket.assigns.chunk_count + 1)
     |> assign(total_chunks: socket.assigns.total_chunks + 1)
     |> assign(avg_chunk_interval: Float.round(avg_interval, 1))
     |> assign(avg_broadcast_time: Float.round(duration_ms, 2))
     |> assign(samples: new_interval_samples)}
  end

  # Catch-all for other messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp attach_telemetry do
    handler_id = "stream-speed-#{inspect(self())}"
    liveview_pid = self()

    # Detach if already exists
    try do
      :telemetry.detach(handler_id)
      :telemetry.detach("#{handler_id}-ttfc")
    catch
      :error, :not_found -> :ok
    end

    # Attach for chunk intervals (streaming speed)
    :telemetry.attach(
      handler_id,
      [:my_app, :openai, :chunk],
      fn _event_name, measurements, metadata, _config ->
        send(liveview_pid, {:telemetry, [:my_app, :openai, :chunk], measurements, metadata})
      end,
      nil
    )

    # Attach for time to first chunk (processing time)
    :telemetry.attach(
      "#{handler_id}-ttfc",
      [:my_app, :openai, :time_to_first_chunk],
      fn _event_name, measurements, metadata, _config ->
        send(
          liveview_pid,
          {:telemetry, [:my_app, :openai, :time_to_first_chunk], measurements, metadata}
        )
      end,
      nil
    )
  end

  defp get_cluster_nodes do
    [Node.self() | Node.list()]
    |> Enum.map(fn node ->
      %{
        name: node,
        ip: node |> to_string() |> String.split("@") |> List.last(),
        connected: Node.ping(node) == :pong
      }
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0f1419] text-gray-100 p-6">
      <!-- Header with Cluster Status -->
      <div class="bg-[#1a1f2e] rounded-lg p-6 mb-6 border border-gray-800">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h1 class="text-2xl font-bold text-white">Streaming Performance Monitor</h1>
            <p class="text-gray-400 text-sm mt-1">Real-time metrics across cluster</p>
          </div>
          <div class="flex items-center gap-2">
            <div class={[
              "px-3 py-1 rounded-full text-xs font-semibold",
              @performance_status == "streaming" && "bg-green-500/20 text-green-400",
              @performance_status == "active" && "bg-blue-500/20 text-blue-400",
              @performance_status == "idle" && "bg-gray-500/20 text-gray-400"
            ]}>
              {String.upcase(@performance_status)}
            </div>
          </div>
        </div>
        
    <!-- Cluster Nodes -->
        <div class="flex gap-2 items-center">
          <span class="text-sm text-gray-400">Nodes:</span>
          <%= for node <- @nodes do %>
            <div class="bg-[#2a2f3e] px-3 py-1 rounded text-sm font-mono flex items-center gap-2">
              <div class={[
                "w-2 h-2 rounded-full",
                node.connected && "bg-green-500",
                !node.connected && "bg-red-500"
              ]}>
              </div>
              {node.ip}
            </div>
          <% end %>
          <span class="text-gray-500 text-sm">{length(@nodes)} connected</span>
        </div>
      </div>
      
    <!-- Metrics Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <!-- Chunk Interval -->
        <div class="bg-[#1a1f2e] rounded-lg p-6 border border-gray-800">
          <div class="text-gray-400 text-sm mb-2">Chunk Interval</div>
          <div class="flex items-baseline gap-2">
            <div class="text-4xl font-bold text-blue-400">
              {@avg_chunk_interval}
            </div>
            <div class="text-gray-500 text-sm">ms</div>
          </div>
          <div class="mt-2 text-xs text-gray-500">
            {if @avg_chunk_interval < 100, do: "⚡ Fast", else: "⏱️ Normal"}
          </div>
        </div>
        
    <!-- Broadcast Time -->
        <div class="bg-[#1a1f2e] rounded-lg p-6 border border-gray-800">
          <div class="text-gray-400 text-sm mb-2">Broadcast Time</div>
          <div class="flex items-baseline gap-2">
            <div class="text-4xl font-bold text-green-400">
              {@avg_broadcast_time}
            </div>
            <div class="text-gray-500 text-sm">ms</div>
          </div>
          <div class="mt-2 text-xs text-gray-500">
            {if @avg_broadcast_time < 5, do: "⚡ Excellent", else: "✓ Good"}
          </div>
        </div>
        
    <!-- Throughput -->
        <div class="bg-[#1a1f2e] rounded-lg p-6 border border-gray-800">
          <div class="text-gray-400 text-sm mb-2">Throughput</div>
          <div class="flex items-baseline gap-2">
            <div class="text-4xl font-bold text-purple-400">
              {@chunks_per_second}
            </div>
            <div class="text-gray-500 text-sm">chunks/s</div>
          </div>
          <div class="mt-2 text-xs text-gray-500">
            {if @chunks_per_second > 5, do: "📈 High", else: "📊 Normal"}
          </div>
        </div>
        
    <!-- Total Chunks -->
        <div class="bg-[#1a1f2e] rounded-lg p-6 border border-gray-800">
          <div class="text-gray-400 text-sm mb-2">Total Chunks</div>
          <div class="flex items-baseline gap-2">
            <div class="text-4xl font-bold text-yellow-400">
              {@total_chunks}
            </div>
            <div class="text-gray-500 text-sm">total</div>
          </div>
          <div class="mt-2 text-xs text-gray-500">
            Since page load
          </div>
        </div>
      </div>
      
    <!-- Performance Details -->
      <div class="bg-[#1a1f2e] rounded-lg p-6 border border-gray-800">
        <h2 class="text-lg font-semibold text-white mb-4">Performance Breakdown</h2>

        <div class="space-y-4">
          <!-- Time to First Chunk -->
          <div class="bg-[#1a1f2e] rounded-lg p-6 border border-gray-800">
            <div class="text-gray-400 text-sm mb-2">Time to First Chunk</div>
            <div class="flex items-baseline gap-2">
              <div class="text-4xl font-bold text-orange-400">
                {@avg_time_to_first_chunk}
              </div>
              <div class="text-gray-500 text-sm">ms</div>
            </div>
            <div class="mt-2 text-xs text-gray-500">
              {if @avg_time_to_first_chunk < 3000, do: "⚡ Fast", else: "⏱️ Normal"}
            </div>
          </div>
          <!-- OpenAI Streaming -->
          <div>
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm text-gray-400">OpenAI Streaming Speed</span>
              <span class="text-sm font-mono text-gray-300">{@avg_chunk_interval}ms</span>
            </div>
            <div class="w-full bg-gray-700 rounded-full h-2">
              <div
                class="bg-blue-500 h-2 rounded-full transition-all duration-300"
                style={"width: #{min(100, (@avg_chunk_interval / 200) * 100)}%"}
              >
              </div>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              {streaming_speed_status(@avg_chunk_interval)}
            </div>
          </div>
          
    <!-- Cluster Broadcasting -->
          <div>
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm text-gray-400">Cluster Broadcast Speed</span>
              <span class="text-sm font-mono text-gray-300">{@avg_broadcast_time}ms</span>
            </div>
            <div class="w-full bg-gray-700 rounded-full h-2">
              <div
                class="bg-green-500 h-2 rounded-full transition-all duration-300"
                style={"width: #{min(100, (@avg_broadcast_time / 10) * 100)}%"}
              >
              </div>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              {broadcast_speed_status(@avg_broadcast_time)}
            </div>
          </div>
          
    <!-- Overall Throughput -->
          <div>
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm text-gray-400">Message Throughput</span>
              <span class="text-sm font-mono text-gray-300">{@chunks_per_second} chunks/s</span>
            </div>
            <div class="w-full bg-gray-700 rounded-full h-2">
              <div
                class="bg-purple-500 h-2 rounded-full transition-all duration-300"
                style={"width: #{min(100, (@chunks_per_second / 20) * 100)}%"}
              >
              </div>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              {throughput_status(@chunks_per_second)}
            </div>
          </div>
        </div>
      </div>
      
    <!-- Info Footer -->
      <div class="mt-6 text-center text-sm text-gray-500">
        <p>Monitoring PubSub broadcasts and GraphQL subscriptions across {length(@nodes)} nodes</p>
        <p class="mt-1">
          Open <a href="/cluster" class="text-blue-400 hover:text-blue-300">/cluster</a>
          in another tab to send test messages
        </p>
      </div>
    </div>
    """
  end

  # Helper functions
  defp streaming_speed_status(interval) when interval < 50, do: "Excellent - Very fast streaming"
  defp streaming_speed_status(interval) when interval < 100, do: "Good - Normal streaming speed"
  defp streaming_speed_status(interval) when interval < 200, do: "Fair - Acceptable speed"
  defp streaming_speed_status(_), do: "Slow - Network or API delay"

  defp broadcast_speed_status(time) when time < 5, do: "⚡ Excellent - Sub-5ms cluster sync"
  defp broadcast_speed_status(time) when time < 10, do: "✓ Good - Fast cluster distribution"
  defp broadcast_speed_status(_), do: "⚠️ Check cluster health"

  defp throughput_status(rate) when rate > 10, do: "🔥 High load - Active streaming"
  defp throughput_status(rate) when rate > 5, do: "📈 Moderate load"
  defp throughput_status(rate) when rate > 0, do: "📊 Light activity"
  defp throughput_status(_), do: "💤 Idle"
end
