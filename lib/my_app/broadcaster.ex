defmodule MyApp.Broadcaster do
  @moduledoc """
  Handles broadcasting messages across the cluster via PubSub
  """

  @pubsub MyApp.PubSub

  @doc """
  Broadcasts a message to all subscribers of a topic across the cluster
  """
  def broadcast(topic, event, payload) do
    # Emit telemetry before broadcast
    :telemetry.execute(
      [:my_app, :pubsub, :broadcast],
      %{count: 1},
      %{topic: topic}
    )

    Phoenix.PubSub.broadcast(@pubsub, topic, {event, payload})
  end

  @doc """
  Broadcasts a message from a specific node
  """
  def broadcast_from(topic, event, payload) do
    Phoenix.PubSub.broadcast_from(@pubsub, self(), topic, {event, payload})
  end

  @doc """
  Subscribes the current process to a topic
  """
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  @doc """
  Unsubscribes the current process from a topic
  """
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic)
  end

  @doc """
  Returns list of connected nodes in the cluster
  """
  def cluster_nodes do
    [Node.self() | Node.list()]
  end

  @doc """
  Returns the current node name
  """
  def current_node do
    Node.self()
  end
end
