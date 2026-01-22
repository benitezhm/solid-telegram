defmodule MyAppWeb.Schema do
  use Absinthe.Schema

  @desc "A chat message"
  object :message do
    field :id, :string
    field :content, :string
    field :username, :string
    field :thread_id, :string
    field :timestamp, :string
  end

  @desc "A thread event (new message or streaming delta)"
  object :thread_event do
    field :message, :string
    field :event_type, :string
    field :username, :string
    field :thread_id, :string
    field :is_stream, :boolean
    field :timestamp, :string
  end

  query do
    @desc "Simple ping for testing"
    field :ping, :string do
      resolve fn _, _ ->
        {:ok, "pong"}
      end
    end
  end

  subscription do
    @desc "Subscribe to thread events (messages and streaming deltas)"
    field :thread_event, :thread_event do
      arg :thread_id, non_null(:string)

      config fn args, _ ->
        {:ok, topic: "thread:#{args.thread_id}"}
      end

      resolve fn payload, _, _ ->
        {:ok, payload}
      end
    end
  end
end
