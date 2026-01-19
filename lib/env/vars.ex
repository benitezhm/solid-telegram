defmodule Env.Vars do
  def env() do
    Application.get_env(:my_app, :env)
  end

  def openai_global_assistant_id() do
    Application.get_env(:my_app, :open_ai)
    |> Keyword.get(:global_assistant_id)
  end

  def openai_global_vector_store_id() do
    Application.get_env(:my_app, :open_ai)
    |> Keyword.get(:global_vector_store_id)
  end
end
