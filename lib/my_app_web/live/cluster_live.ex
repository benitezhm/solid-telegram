defmodule MyAppWeb.ClusterLive do
  use MyAppWeb, :live_view

  alias MyApp.Services.OpenAI

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MyApp.Broadcaster.subscribe("cluster:messages")
      MyApp.Broadcaster.subscribe("cluster:typing")
      MyApp.Broadcaster.subscribe("cluster:threads")
    end

    {:ok,
     socket
     |> assign(:threads, [])
     |> assign(:selected_thread, nil)
     |> assign(:show_create_thread, false)
     |> assign(:thread_form, to_form(%{"title" => ""}))
     |> assign(:messages, [])
     |> assign(:nodes, MyApp.Broadcaster.cluster_nodes())
     |> assign(:current_node, MyApp.Broadcaster.current_node())
     |> assign(:typing_status, %{})
     |> assign(:form, to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_event("show_create_thread", _params, socket) do
    {:noreply, assign(socket, :show_create_thread, true)}
  end

  @impl true
  def handle_event("cancel_create_thread", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_thread, false)
     |> assign(:thread_form, to_form(%{"title" => ""}))}
  end

  @impl true
  def handle_event("create_thread", %{"title" => title}, socket) do
    if String.trim(title) != "" do
      {:ok, %{openai_thread_id: thread_id}} = OpenAI.create_thread()

      payload = %{
        id: thread_id,
        title: title,
        created_by: Node.self(),
        created_at: DateTime.utc_now() |> DateTime.to_string(),
        message_count: 0
      }

      MyApp.Broadcaster.broadcast("cluster:threads", :new_thread, payload)

      {:noreply,
       socket
       |> assign(:show_create_thread, false)
       |> assign(:thread_form, to_form(%{"title" => ""}))
       |> assign(:selected_thread, thread_id)
       |> assign(:messages, [])}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_thread", %{"thread_id" => thread_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_thread, thread_id)
     |> assign(:messages, [])
     |> assign(:form, to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_event("typing", %{"message" => message}, socket) do
    if socket.assigns.selected_thread do
      payload = %{
        from: Node.self(),
        message: message,
        thread_id: socket.assigns.selected_thread,
        timestamp: System.monotonic_time(:millisecond)
      }

      MyApp.Broadcaster.broadcast("cluster:typing", :user_typing, payload)
    end

    {:noreply, assign(socket, :form, to_form(%{"message" => message}))}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if socket.assigns.selected_thread && String.trim(message) != "" do
      payload = %{
        id: Ecto.UUID.generate(),
        thread_id: socket.assigns.selected_thread,
        from: Node.self(),
        message: message,
        timestamp: DateTime.utc_now() |> DateTime.to_string()
      }

      OpenAI.stream(%{
        question: message,
        openai_thread_id: socket.assigns.selected_thread,
        payload: payload
      })

      MyApp.Broadcaster.broadcast("cluster:messages", :new_message, payload)
    end

    # Clear typing status for this node
    if socket.assigns.selected_thread do
      clear_payload = %{
        from: Node.self(),
        message: "",
        thread_id: socket.assigns.selected_thread,
        timestamp: System.monotonic_time(:millisecond)
      }

      MyApp.Broadcaster.broadcast("cluster:typing", :user_typing, clear_payload)
    end

    {:noreply, assign(socket, :form, to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_event("refresh_nodes", _params, socket) do
    {:noreply, assign(socket, :nodes, MyApp.Broadcaster.cluster_nodes())}
  end

  @impl true
  def handle_info({:new_thread, payload}, socket) do
    threads = [payload | socket.assigns.threads]

    {:noreply, assign(socket, :threads, threads)}
  end

  @impl true
  def handle_info({:new_message, payload}, socket) do
    if payload.thread_id == socket.assigns.selected_thread do
      messages = [payload | socket.assigns.messages] |> Enum.take(50)

      {:noreply, assign(socket, :messages, messages)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:user_typing, payload}, socket) do
    if payload.thread_id == socket.assigns.selected_thread do
      typing_status =
        if String.trim(payload.message) == "" do
          socket.assigns.typing_status
          |> Map.delete(payload.from)
        else
          Map.put(socket.assigns.typing_status, payload.from, payload)
        end

      {:noreply, assign(socket, :typing_status, typing_status)}
    else
      {:noreply, socket}
    end
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
          <p class="text-purple-300 text-lg">Real-time Erlang Distribution & PubSub with Threads</p>
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
        
    <!-- Threads Section -->
        <div class="bg-gradient-to-r from-indigo-600 to-indigo-800 rounded-2xl shadow-2xl p-6 mb-6 border border-indigo-400">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-2xl font-bold text-white flex items-center gap-2">
              <span class="text-3xl">📌</span> Threads
            </h2>
            <button
              phx-click="show_create_thread"
              class="bg-white text-indigo-700 px-6 py-2 rounded-lg font-semibold hover:bg-indigo-50 transition-all transform hover:scale-105 shadow-lg"
            >
              ➕ New Thread
            </button>
          </div>
          
    <!-- Create Thread Modal -->
          <%= if @show_create_thread do %>
            <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
              <div class="bg-white rounded-2xl shadow-2xl p-6 w-full max-w-md mx-4">
                <h3 class="text-2xl font-bold text-slate-800 mb-4">Create New Thread</h3>

                <.form for={@thread_form} phx-submit="create_thread" class="space-y-4">
                  <input
                    type="text"
                    name="title"
                    value={@thread_form[:title].value}
                    placeholder="Thread title..."
                    class="w-full border-2 border-indigo-300 rounded-xl px-4 py-3 text-lg focus:outline-none focus:ring-4 focus:ring-indigo-300"
                    autocomplete="off"
                  />

                  <div class="flex gap-3">
                    <button
                      type="submit"
                      class="flex-1 bg-indigo-600 text-white px-6 py-3 rounded-xl font-semibold hover:bg-indigo-700 transition-all"
                    >
                      Create 🚀
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_create_thread"
                      class="flex-1 bg-slate-300 text-slate-800 px-6 py-3 rounded-xl font-semibold hover:bg-slate-400 transition-all"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          <% end %>
          
    <!-- Threads List -->
          <%= if @threads == [] do %>
            <div class="text-center py-8">
              <p class="text-indigo-200 text-lg">No threads yet. Create one to get started!</p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <%= for thread <- @threads do %>
                <button
                  phx-click="select_thread"
                  phx-value-thread_id={thread.id}
                  class={[
                    "text-left p-4 rounded-lg border-2 transition-all transform hover:scale-105",
                    if @selected_thread == thread.id do
                      "bg-white border-indigo-500 shadow-lg"
                    else
                      "bg-white/10 border-white/20 hover:bg-white/20"
                    end
                  ]}
                >
                  <h3 class={[
                    "font-bold text-lg",
                    if @selected_thread == thread.id do
                      "text-indigo-700"
                    else
                      "text-white"
                    end
                  ]}>
                    {thread.title}
                  </h3>
                  <p class={[
                    "text-sm mt-1",
                    if @selected_thread == thread.id do
                      "text-slate-600"
                    else
                      "text-indigo-200"
                    end
                  ]}>
                    Created by {thread.created_by}
                  </p>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Message Input Card (only show if thread selected) -->
        <%= if @selected_thread do %>
          <div class="bg-gradient-to-r from-green-600 to-emerald-700 rounded-2xl shadow-2xl p-6 mb-6 border border-green-400">
            <h2 class="text-2xl font-bold text-white mb-4 flex items-center gap-2">
              <span class="text-3xl">💬</span> Send Message
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
              Messages <span class="text-sm font-normal text-slate-500">(in this thread)</span>
            </h2>

            <div class="space-y-3 max-h-[500px] overflow-y-auto pr-2">
              <%= if @messages == [] do %>
                <div class="text-center py-12">
                  <div class="text-6xl mb-4">📭</div>
                  <p class="text-slate-400 text-lg italic">
                    No messages yet. Start the conversation!
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
        <% else %>
          <!-- No Thread Selected Message -->
          <div class="bg-white rounded-2xl shadow-2xl p-12 text-center border-2 border-slate-300">
            <div class="text-6xl mb-4">🧵</div>
            <h3 class="text-2xl font-bold text-slate-800 mb-2">No Thread Selected</h3>
            <p class="text-slate-600 text-lg">
              Create a new thread or select an existing one to start messaging!
            </p>
          </div>
        <% end %>
        
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
