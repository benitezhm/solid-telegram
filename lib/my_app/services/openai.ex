defmodule MyApp.Services.OpenAI do
  require Logger
  alias MyApp.Services.OpenAI

  def create_message(
        %{
          question: question_message,
          openai_thread_id: openai_thread_id,
          payload: _payload
        } = params
      ) do
    openai_thread_id
    |> OpenAi.Assistants.create_message(%OpenAi.Message.CreateRequest{
      role: "user",
      content: question_message
    })
    |> OpenAI.simplify_error()
    |> case do
      {:ok, _message} ->
        stream(params)

      {:error, error} ->
        {:error, error}
    end
  end

  def stream(%{
        question: question_message,
        openai_thread_id: openai_thread_id,
        payload: payload
      }) do
    Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
      %{
        openai_thread_id: openai_thread_id,
        ai_assistant_id: Env.Vars.openai_assistant_id()
      }
      |> OpenAI.Run.create(
        stream: true,
        tool_choice: %{type: "file_search"}
      )
      |> Stream.each(fn
        {:ok, %{event: "thread.message.completed", data: answer} = _event} ->
          # :timer.sleep(500)
          # Logger.info("🔔 COMPLETED EVENT RECEIVED: #{inspect(event)}")
          {:ok, answer} = text(answer)

          payload =
            payload
            |> Map.put(:message, answer)
            |> Map.put(:from, "pmb-team@pickmybrain.com")
            |> Map.put(:streaming_responses, %{})

          # broadcast message here (PubSub for LiveView)
          MyApp.Broadcaster.broadcast("cluster:messages", :new_message, payload)

          # Publish to GraphQL subscriptions
          Absinthe.Subscription.publish(
            MyAppWeb.Endpoint,
            %{
              message: answer,
              event_type: "message",
              username: payload.from,
              thread_id: payload.thread_id,
              is_stream: false,
              timestamp: payload.timestamp
            },
            thread_event: "thread:#{payload.thread_id}"
          )

        {:ok, %{event: "thread.message.delta", data: %{delta: delta} = _answer} = _event} ->
          # :timer.sleep(100)
          {:ok, delta} = text(delta)
          # Logger.info("🔔 DELTA EVENT RECEIVED: #{inspect(delta)}")

          payload =
            payload
            |> Map.put(:message, delta)
            |> Map.put(:from, "pmb-team@pickmybrain.com")
            |> Map.put(:is_stream, true)
            |> Map.put(:timestamp, System.monotonic_time(:millisecond))

          # PubSub for LiveView
          MyApp.Broadcaster.broadcast("cluster:typing", :stream_delta, payload)

          # Publish to GraphQL subscriptions
          Absinthe.Subscription.publish(
            MyAppWeb.Endpoint,
            %{
              message: delta,
              event_type: "stream_delta",
              username: payload.from,
              thread_id: payload.thread_id,
              is_stream: true,
              timestamp: to_string(payload.timestamp)
            },
            thread_event: "thread:#{payload.thread_id}"
          )

        {:ok, _message} ->
          # MyApp.Broadcaster.broadcast("cluster:messages", :new_message, payload)
          :ok

        {:error, error} ->
          Logger.error("Error: #{inspect(error)}")
      end)
      |> Stream.run()
    end)

    {:ok, %{question: question_message, answer: nil}}
  end

  def create_thread() do
    __MODULE__.Thread.create()
    |> case do
      {:ok, %OpenAi.Thread{id: openai_thread_id}} ->
        {:ok, %{openai_thread_id: openai_thread_id}}

      {:error, error} ->
        Logger.error("Error creating thread #{inspect(error)}")

        {:error, %{message: "thread_creation_failed"}}
    end
  end

  def simplify_error({:ok, res}), do: {:ok, res}

  def simplify_error({:error, %{body: %{"error" => %{"message" => error}}}}),
    do: {:error, "AI error: " <> error}

  def simplify_error({:error, %{body: %{"error" => error}}}),
    do: {:error, "AI error: " <> inspect(error)}

  def simplify_error({:error, %{body: error}}), do: {:error, "AI error: " <> inspect(error)}
  def simplify_error({:error, error}), do: {:error, "AI error: " <> inspect(error)}
  def simplify_error(_), do: {:error, "AI error: unknown"}

  defp text(%{content: [%{text: %{value: text}} | _]}) do
    {:ok, text}
  end

  defp text(_data), do: {:ok, ""}
end
