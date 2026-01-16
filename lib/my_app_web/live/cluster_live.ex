defmodule MyAppWeb.ClusterLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MyApp.Broadcaster.subscribe("cluster:messages")
      MyApp.Broadcaster.subscribe("cluster:typing")
    end

    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:nodes, MyApp.Broadcaster.cluster_nodes())
     |> assign(:current_node, MyApp.Broadcaster.current_node())
     |> assign(:typing_status, %{})
     |> assign(:form, to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_event("typing", %{"message" => message}, socket) do
    payload = %{
      from: Node.self(),
      message: message,
      timestamp: System.monotonic_time(:millisecond)
    }

    MyApp.Broadcaster.broadcast("cluster:typing", :user_typing, payload)

    {:noreply, assign(socket, :form, to_form(%{"message" => message}))}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      payload = %{
        from: Node.self(),
        message: message,
        timestamp: DateTime.utc_now() |> DateTime.to_string()
      }

      MyApp.Broadcaster.broadcast("cluster:messages", :new_message, payload)
    end

    # Clear typing status for this node
    clear_payload = %{
      from: Node.self(),
      message: "",
      timestamp: System.monotonic_time(:millisecond)
    }

    MyApp.Broadcaster.broadcast("cluster:typing", :user_typing, clear_payload)

    {:noreply,
     socket
     |> assign(:form, to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_event("refresh_nodes", _params, socket) do
    {:noreply, assign(socket, :nodes, MyApp.Broadcaster.cluster_nodes())}
  end

  @impl true
  def handle_info({:new_message, payload}, socket) do
    messages = [payload | socket.assigns.messages] |> Enum.take(50)

    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_info({:user_typing, payload}, socket) do
    typing_status =
      if String.trim(payload.message) == "" do
        socket.assigns.typing_status
        |> Map.delete(payload.from)
      else
        Map.put(socket.assigns.typing_status, payload.from, payload)
      end

    {:noreply, assign(socket, :typing_status, typing_status)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
      <div class="max-w-6xl mx-auto p-8">
        <!-- Header -->
        <div class="text-center mb-8">
          <h1 class="text-5xl font-bold text-white mb-2">
            Phoenix Cluster Demo
          </h1>
          <p class="text-purple-300 text-lg">Real-time Erlang Distribution & PubSub</p>
        </div>

    <!-- Cluster Information Card -->
        <div class="bg-gradient-to-r from-blue-600 to-blue-800 rounded-2xl shadow-2xl p-6 mb-6 border border-blue-400">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-2xl font-bold text-white flex items-center gap-2">
              <span class="text-3xl">🌐</span> Cluster Status
            </h2>
            <button
              phx-click="refresh_nodes"
              class="bg-white text-blue-700 px-6 py-2 rounded-lg font-semibold hover:bg-blue-50 transition-all transform hover:scale-105 shadow-lg"
            >
              🔄 Refresh
            </button>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
            <div class="bg-white/10 backdrop-blur rounded-xl p-4 border border-white/20">
              <p class="text-blue-200 text-sm mb-1">Current Node</p>
              <p class="text-white text-xl font-mono font-bold">{@current_node}</p>
            </div>
            <div class="bg-white/10 backdrop-blur rounded-xl p-4 border border-white/20">
              <p class="text-blue-200 text-sm mb-1">Connected Nodes</p>
              <p class="text-white text-xl font-bold">{length(@nodes)} Node(s)</p>
            </div>
          </div>

          <div class="bg-white/10 backdrop-blur rounded-xl p-4 border border-white/20">
            <p class="text-blue-200 text-sm mb-3 font-semibold">All Nodes in Cluster:</p>
            <div class="flex flex-wrap gap-2">
              <%= for node <- @nodes do %>
                <span class={[
                  "px-4 py-2 rounded-lg font-mono text-sm font-semibold shadow-md",
                  if node == @current_node do
                    "bg-green-500 text-white ring-2 ring-green-300"
                  else
                    "bg-white/20 text-white"
                  end
                ]}>
                  <%= if node == @current_node do %>
                    ⭐ {node} (YOU)
                  <% else %>
                    🔗 {node}
                  <% end %>
                </span>
              <% end %>
            </div>
          </div>
        </div>

    <!-- Message Input Card -->
        <div class="bg-gradient-to-r from-green-600 to-emerald-700 rounded-2xl shadow-2xl p-6 mb-6 border border-green-400">
          <h2 class="text-2xl font-bold text-white mb-4 flex items-center gap-2">
            <span class="text-3xl">💬</span> Send Message Across Cluster
          </h2>
          <.form
            for={@form}
            id="message-form"
            phx-submit="send_message"
            phx-change="typing"
            class="flex gap-3"
          >
            <input
              type="text"
              name="message"
              value={@form[:message].value}
              placeholder="Type your message here..."
              class="flex-1 border-2 border-green-300 rounded-xl px-6 py-4 text-lg focus:outline-none focus:ring-4 focus:ring-green-300 shadow-lg"
              autocomplete="off"
            />
            <button
              type="submit"
              class="bg-white text-green-700 px-8 py-4 rounded-xl font-bold text-lg hover:bg-green-50 transition-all transform hover:scale-105 shadow-xl"
            >
              Send 🚀
            </button>
          </.form>
          <p class="text-green-100 text-sm mt-3">
            Messages will appear instantly on all connected nodes!
          </p>
        </div>

    <!-- Typing Indicators -->
        <%= if map_size(@typing_status) > 0 and @typing_status |> Map.values() |> List.first() |> Map.get(:from) != @current_node do %>
          <div class="bg-gradient-to-r from-amber-500 to-orange-600 rounded-2xl shadow-2xl p-4 mb-6 border border-amber-400">
            <div class="space-y-2">
              <%= for {node, typing_data} <- @typing_status do %>
                <%= if node != @current_node and String.trim(typing_data.message) != "" do %>
                  <div class="bg-white/20 backdrop-blur rounded-xl p-4 border border-white/20">
                    <div class="flex items-center gap-3">
                      <span class="text-white font-bold font-mono text-sm">
                        🔗 {node}
                      </span>
                      <span class="text-white/80 text-sm">is typing:</span>
                      <span class="text-white font-medium flex-1">
                        {typing_data.message}
                      </span>
                      <span class="text-amber-200 animate-pulse">✍️</span>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

    <!-- Messages Card -->
        <div class="bg-white rounded-2xl shadow-2xl p-6 border-2 border-purple-300">
          <h2 class="text-2xl font-bold text-slate-800 mb-4 flex items-center gap-2">
            <span class="text-3xl">📨</span>
            Live Messages <span class="text-sm font-normal text-slate-500">(across all nodes)</span>
          </h2>

          <div class="space-y-3 max-h-[500px] overflow-y-auto pr-2">
            <%= if @messages == [] do %>
              <div class="text-center py-12">
                <div class="text-6xl mb-4">📭</div>
                <p class="text-slate-400 text-lg italic">
                  No messages yet. Send one to test the cluster!
                </p>
              </div>
            <% else %>
              <%= for msg <- @messages do %>
                <div class={[
                  "rounded-xl p-5 shadow-lg border-2 transition-all hover:shadow-xl",
                  if String.contains?(to_string(msg.from), to_string(@current_node)) do
                    "bg-gradient-to-r from-purple-100 to-pink-100 border-purple-300"
                  else
                    "bg-gradient-to-r from-blue-50 to-cyan-50 border-blue-300"
                  end
                ]}>
                  <div class="flex justify-between items-start mb-2">
                    <span class={[
                      "font-bold text-sm px-3 py-1 rounded-full",
                      if String.contains?(to_string(msg.from), to_string(@current_node)) do
                        "bg-purple-600 text-white"
                      else
                        "bg-blue-600 text-white"
                      end
                    ]}>
                      <%= if String.contains?(to_string(msg.from), to_string(@current_node)) do %>
                        ⭐ {msg.from}
                      <% else %>
                        🔗 {msg.from}
                      <% end %>
                    </span>
                    <span class="text-xs text-slate-500 font-mono bg-white px-2 py-1 rounded">
                      {msg.timestamp}
                    </span>
                  </div>
                  <p class="text-slate-800 text-lg font-medium pl-1">{msg.message}</p>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

    <!-- Footer Info -->
        <div class="mt-6 text-center">
          <p class="text-purple-300 text-sm">
            Open <strong class="text-white">localhost:4000/cluster</strong>
            and <strong class="text-white">localhost:4001/cluster</strong>
            in different tabs to see real-time sync!
          </p>
        </div>
      </div>
    </div>
    """
  end
end
