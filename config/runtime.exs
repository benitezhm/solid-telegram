import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/my_app start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :my_app, MyAppWeb.Endpoint, server: true
end

config :my_app, MyAppWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false

if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL")

  if database_url do
    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :my_app, MyApp.Repo,
      # ssl: true,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      # For machines with several cores, consider starting multiple pools of `pool_size`
      # pool_count: 4,
      socket_options: maybe_ipv6
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :my_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Configure libcluster
  # Supports two strategies:
  # 1. EPMD with static nodes (Docker Compose): Set CLUSTER_NODES=my_app@app1,my_app@app2,my_app@app3
  # 2. Kubernetes DNS: Set DNS_CLUSTER_QUERY=my-app-headless.default.svc.cluster.local
  cluster_nodes = System.get_env("CLUSTER_NODES")
  dns_cluster_query = System.get_env("DNS_CLUSTER_QUERY")

  topologies =
    cond do
      dns_cluster_query != nil ->
        # Kubernetes DNS strategy
        [
          k8s_dns: [
            strategy: Cluster.Strategy.Kubernetes.DNS,
            config: [
              service: dns_cluster_query,
              application_name: "my_app",
              polling_interval: 5_000
            ]
          ]
        ]

      cluster_nodes != nil ->
        # EPMD strategy with explicit node list (Docker Compose)
        nodes =
          cluster_nodes
          |> String.split(",")
          |> Enum.map(&String.to_atom/1)

        [
          epmd: [
            strategy: Cluster.Strategy.Epmd,
            config: [
              hosts: nodes
            ]
          ]
        ]

      true ->
        # Fallback to Gossip (local development)
        [
          gossip: [
            strategy: Cluster.Strategy.Gossip,
            config: [
              port: 45892,
              if_addr: "0.0.0.0",
              multicast_addr: "230.1.1.251",
              multicast_ttl: 1,
              secret: System.get_env("CLUSTER_SECRET") || "cluster_secret"
            ]
          ]
        ]
    end

  config :libcluster, topologies: topologies

  config :oapi_open_ai,
    # find it at https://platform.openai.com/account/api-keys
    api_key: System.get_env("OPENAI_API_KEY"),
    # optional, other clients allow overriding via the OPENAI_API_URL/OPENAI_API_BASE environment variable,
    # if unset the the default is https://api.openai.com/v1
    # base_url: System.get_env("OPENAI_API_URL"),
    # optional, use when required by an OpenAI API beta, e.g.:
    http_headers: [
      {"OpenAI-Beta", "assistants=v2"}
    ],
    # optional, passed to HTTPoison.Request options
    http_options: [recv_timeout: 30_000]

  config :my_app, :open_ai,
    assistant_id: System.get_env("OPENAI_ASSISTANT_ID", ""),
    vector_store_id: System.get_env("OPENAI_VECTOR_STORE_ID", "")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :my_app, MyAppWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :my_app, MyAppWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :my_app, MyApp.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
