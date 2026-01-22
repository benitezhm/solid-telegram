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
     |> assign(:streaming_responses, %{})
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
     |> assign(:typing_status, %{})
     |> assign(:streaming_responses, %{})
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

      OpenAI.create_message(%{
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

      {:noreply, assign(socket, :messages, messages) |> assign(:streaming_responses, %{})}
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
  def handle_info({:stream_delta, payload}, socket) do
    if payload.thread_id == socket.assigns.selected_thread do
      streaming_responses = socket.assigns.streaming_responses
      node_key = payload.from

      # Get existing accumulated message or start fresh
      existing = Map.get(streaming_responses, node_key, %{message: ""})

      # Append the new delta to the accumulated message
      accumulated_message = existing.message <> payload.message

      updated_response =
        payload
        |> Map.put(:message, accumulated_message)
        |> Map.put(:is_stream, true)

      new_streaming_responses = Map.put(streaming_responses, node_key, updated_response)

      {:noreply, assign(socket, :streaming_responses, new_streaming_responses)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-slate-950 via-slate-900 to-slate-950 pb-24">
      <div class="max-w-4xl mx-auto px-4 py-4">
        <!-- Compact Cluster Status Bar -->
        <div class="bg-slate-800/80 backdrop-blur rounded-lg shadow-md px-4 py-2 mb-4 border border-slate-700">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4 text-xs">
              <span class="text-slate-400">Node:</span>
              <span class="text-teal-400 font-mono font-medium">{@current_node}</span>
              <span class="text-slate-500">|</span>
              <span class="text-slate-400">{length(@nodes)} connected</span>
            </div>
            <div class="flex items-center gap-2">
              <%= for node <- @nodes do %>
                <span class={[
                  "px-2 py-0.5 rounded text-xs font-mono",
                  if node == @current_node do
                    "bg-teal-500/20 text-teal-400 ring-1 ring-teal-500/40"
                  else
                    "bg-slate-800 text-slate-400"
                  end
                ]}>
                  {node}
                </span>
              <% end %>
              <button
                phx-click="refresh_nodes"
                class="ml-2 text-slate-400 hover:text-white text-xs px-2 py-1 rounded hover:bg-slate-700 transition-colors"
              >
                ↻
              </button>
            </div>
          </div>
        </div>

        <!-- Compact Threads Section -->
        <div class="bg-slate-800/60 backdrop-blur rounded-lg shadow-md px-4 py-3 mb-4 border border-slate-700">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-sm font-semibold text-slate-300">Threads</h2>
            <button
              phx-click="show_create_thread"
              class="text-xs bg-indigo-600 hover:bg-indigo-700 text-white px-3 py-1 rounded transition-colors"
            >
              + New
            </button>
          </div>

          <!-- Create Thread Modal -->
          <%= if @show_create_thread do %>
            <div class="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
              <div class="bg-slate-800 rounded-lg shadow-xl p-4 w-full max-w-sm mx-4 border border-slate-600">
                <h3 class="text-base font-semibold text-white mb-3">New Thread</h3>
                <.form for={@thread_form} phx-submit="create_thread" class="space-y-3">
                  <input
                    type="text"
                    name="title"
                    value={@thread_form[:title].value}
                    placeholder="Thread title..."
                    class="w-full bg-slate-700 border border-slate-600 rounded px-3 py-2 text-sm text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    autocomplete="off"
                  />
                  <div class="flex gap-2">
                    <button
                      type="submit"
                      class="flex-1 bg-indigo-600 text-white px-3 py-2 rounded text-sm font-medium hover:bg-indigo-700 transition-colors"
                    >
                      Create
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_create_thread"
                      class="flex-1 bg-slate-600 text-slate-200 px-3 py-2 rounded text-sm font-medium hover:bg-slate-500 transition-colors"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          <% end %>

          <!-- Threads List - Horizontal Scroll -->
          <%= if @threads == [] do %>
            <p class="text-slate-500 text-xs py-2">No threads yet. Create one to get started.</p>
          <% else %>
            <div class="flex gap-2 overflow-x-auto pb-1 scrollbar-thin">
              <%= for thread <- @threads do %>
                <button
                  phx-click="select_thread"
                  phx-value-thread_id={thread.id}
                  class={[
                    "flex-shrink-0 text-left px-3 py-2 rounded border transition-all text-xs",
                    if @selected_thread == thread.id do
                      "bg-indigo-600 border-indigo-500 text-white"
                    else
                      "bg-slate-700/50 border-slate-600 text-slate-300 hover:bg-slate-700"
                    end
                  ]}
                >
                  <div class="font-medium truncate max-w-[150px]">{thread.title}</div>
                  <div class={[
                    "text-xs mt-0.5 truncate max-w-[150px]",
                    if(@selected_thread == thread.id, do: "text-indigo-200", else: "text-slate-500")
                  ]}>
                    {thread.created_by}
                  </div>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @selected_thread do %>
          <!-- Messages Card - Main Focus -->
          <div class="bg-slate-800/80 backdrop-blur rounded-lg shadow border border-slate-700">
            <div class="px-4 py-3 border-b border-slate-700">
              <div class="flex items-center justify-between">
                <h2 class="text-sm font-semibold text-slate-300">Messages</h2>
                <code class="text-xs text-slate-500 font-mono bg-slate-900/50 px-2 py-0.5 rounded select-all">{@selected_thread}</code>
              </div>
            </div>

            <div id="messages-container" phx-hook="ScrollToBottom" class="p-4 space-y-3 max-h-[65vh] overflow-y-auto">
              <%= if @messages == [] do %>
                <div class="text-center py-12">
                  <div class="text-4xl mb-3 opacity-50">💬</div>
                  <p class="text-slate-500 text-sm">No messages yet. Start the conversation!</p>
                </div>
              <% else %>
                <%= for msg <- Enum.reverse(@messages) do %>
                  <div class={[
                    "rounded-lg p-3 border transition-all",
                    if String.contains?(to_string(msg.from), to_string(@current_node)) do
                      "bg-indigo-950/40 border-indigo-800/40"
                    else
                      "bg-slate-800/60 border-slate-700/60"
                    end
                  ]}>
                    <div class="flex justify-between items-center mb-1.5">
                      <span class={[
                        "text-xs font-medium px-2 py-0.5 rounded",
                        if String.contains?(to_string(msg.from), to_string(@current_node)) do
                          "bg-indigo-600/40 text-indigo-300"
                        else
                          "bg-slate-700/60 text-slate-400"
                        end
                      ]}>
                        {msg.from}
                      </span>
                      <span class="text-xs text-slate-500 font-mono">{msg.timestamp}</span>
                    </div>
                    <p class="text-slate-200 text-sm pl-0.5">{msg.message}</p>
                  </div>
                <% end %>
              <% end %>
              <!-- Streaming AI Response -->
              <%= for {_node, response_data} <- @streaming_responses do %>
                <div class="rounded-lg p-3 border transition-all bg-teal-950/30 border-teal-800/40">
                  <div class="flex justify-between items-center mb-1.5">
                    <span class="text-xs font-medium px-2 py-0.5 rounded bg-teal-600/40 text-teal-300">
                      {response_data.from}
                    </span>
                    <span class="text-xs text-teal-400 animate-pulse">streaming...</span>
                  </div>
                  <p class="text-slate-200 text-sm pl-0.5">
                    {response_data.message}<span class="text-teal-400 animate-pulse">▌</span>
                  </p>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <!-- No Thread Selected -->
          <div class="bg-slate-800/60 backdrop-blur rounded-lg shadow-md p-8 text-center border border-slate-700">
            <div class="text-3xl mb-3 opacity-50">🧵</div>
            <h3 class="text-base font-medium text-slate-300 mb-1">No Thread Selected</h3>
            <p class="text-slate-500 text-sm">Create or select a thread to start messaging.</p>
          </div>
        <% end %>

      </div>

      <!-- Fixed Bottom Section -->
      <div class="fixed bottom-0 left-0 right-0 bg-slate-950/95 backdrop-blur border-t border-slate-800 py-3 px-4">
        <div class="max-w-4xl mx-auto">
          <%= if @selected_thread do %>
            <.form
              for={@form}
              id="message-form"
              phx-submit="send_message"
              phx-change="typing"
              class="flex gap-2"
            >
              <input
                type="text"
                name="message"
                value={@form[:message].value}
                placeholder="Type a message..."
                class="flex-1 bg-slate-800/80 border border-slate-700 rounded-lg px-4 py-2.5 text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:border-indigo-500/50"
                autocomplete="off"
              />
              <button
                type="submit"
                class="bg-indigo-600 hover:bg-indigo-500 text-white px-5 py-2.5 rounded-lg text-sm font-medium transition-colors"
              >
                Send
              </button>
            </.form>
          <% end %>
          <p class="text-slate-600 text-xs text-center mt-2">
            Open <span class="text-slate-500">localhost:4000/cluster</span> and
            <span class="text-slate-500">localhost:4001/cluster</span> to see real-time sync
          </p>
        </div>
      </div>
    </div>
    """
  end
end
