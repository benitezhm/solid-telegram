defmodule MyApp.Services.OpenAI.Run do
  alias MyApp.Services.OpenAI

  def create(
        %{
          openai_thread_id: openai_thread_id,
          ai_assistant_id: assistant_id
        },
        opts \\ []
      ) do
    stream_to = Keyword.get(opts, :stream_to, self())
    tool_choice = Keyword.get(opts, :tool_choice, "auto")

    request =
      %OpenAi.Run.CreateRequest{
        assistant_id: assistant_id,
        additional_instructions: "",
        # additional_instructions: create_instructions(chat_user, bot_owner, helper_prompt),
        tool_choice: tool_choice
      }

    # |> attach_vector_store()

    opts
    |> Keyword.get(:stream, false)
    |> if do
      openai_thread_id
      |> OpenAi.Assistants.create_run(
        request
        |> Map.put(:stream, true),
        stream_to: stream_to
      )
    else
      openai_thread_id
      |> OpenAi.Assistants.create_run(request)
      |> OpenAI.simplify_error()
    end
  end

  # defp attach_vector_store(request) do
  #   request
  #   |> Map.put(:tool_resources, %OpenAi.Assistant.Tool.File.Search{
  #     file_search: %OpenAi.Assistant.Tool.Resources.FileSearch{
  #       vector_store_ids: [Env.Vars.openai_vector_store_id()]
  #     }
  #   })
  # end
end
