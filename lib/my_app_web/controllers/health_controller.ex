defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", node: Node.self()})
  end
end
