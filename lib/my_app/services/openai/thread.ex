defmodule MyApp.Services.OpenAI.Thread do
  require Logger
  alias MyApp.Services.OpenAI

  @type thread_id :: String.t()

  @doc """
  Creates a thread for global chatbot (all user data included)
  """
  @spec create() :: {:ok, OpenAi.Thread.t()} | {:error, any()}
  def create() do
    %OpenAi.Thread.CreateRequest{
      tool_resources: %OpenAi.Thread.CreateRequest.ToolResources{
        file_search: %{
          "vector_store_ids" => [Env.Vars.openai_vector_store_id()]
        }
      }
    }
    |> OpenAi.Assistants.create_thread()
    |> OpenAI.simplify_error()
  end
end
