defmodule MyApp.Services.OpenAI do
  require Logger
  alias MyApp.Services.OpenAI

  # defdelegate create_message(create_params, opts \\ []), to: __MODULE__.Messages, as: :create

  def stream(%{
        question: question_message,
        openai_thread_id: openai_thread_id,
        payload: payload
      }) do
    {:ok, task_pid} =
      Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
        %{
          openai_thread_id: openai_thread_id,
          ai_assistant_id: Env.Vars.openai_global_assistant_id()
        }
        |> OpenAI.Run.create(
          stream: true,
          tool_choice: %{type: "file_search"}
        )
        |> Stream.each(fn
          {:ok, %{event: "thread.message.completed", data: answer} = event} ->
            Logger.info("🔔 COMPLETED EVENT RECEIVED: #{inspect(event)}")
            {:ok, answer} = text(answer)
            payload = Map.put(payload, :message, answer)

            # broadcast message here
            MyApp.Broadcaster.broadcast("cluster:messages", :new_message, payload)

          {:ok, %{event: "thread.message.delta", data: %{delta: delta} = _answer} = _event} ->
            {:ok, delta} = text(delta)
            Logger.info("🔔 DELTA EVENT RECEIVED: #{inspect(delta)}")

            MyApp.Broadcaster.broadcast(
              "cluster:typing",
              :user_typing,
              payload |> Map.put(:message, delta)
            )

          {:ok, _message} ->
            # MyApp.Broadcaster.broadcast("cluster:messages", :new_message, payload)
            :ok

          {:error, error} ->
            Logger.error("Error: #{inspect(error)}")
        end)
        |> Stream.run()
      end)

    {:ok, %{question: question_message, answer: nil, task_pid: task_pid, prompts: nil}}
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
