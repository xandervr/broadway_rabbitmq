defmodule BroadwayRabbitMQ.AmqpClientTest do
  use ExUnit.Case

  alias BroadwayRabbitMQ.AmqpClient

  test "default options" do
    assert {:ok,
            %{
              connection: [],
              qos: [prefetch_count: 50],
              metadata: [],
              bindings: [],
              declare_opts: nil,
              queue: "queue",
              after_connect: after_connect
            }} = AmqpClient.init(queue: "queue")

    assert after_connect.(:channel) == :ok
  end

  test "connection name" do
    assert {:ok, %{name: "conn_name"}} = AmqpClient.init(queue: "queue", name: "conn_name")
  end

  describe "validate init options" do
    test "supported options" do
      after_connect = fn _ -> :ok end

      connection = [
        username: nil,
        password: nil,
        virtual_host: nil,
        host: nil,
        port: nil,
        channel_max: nil,
        frame_max: nil,
        heartbeat: nil,
        connection_timeout: nil,
        ssl_options: nil,
        client_properties: nil,
        socket_options: nil
      ]

      qos = [
        prefetch_size: 1,
        prefetch_count: 1
      ]

      options = [
        queue: "queue",
        connection: connection,
        qos: qos,
        after_connect: after_connect,
        consume_options: [no_ack: true, exclusive: false]
      ]

      metadata = []

      assert AmqpClient.init(options) ==
               {:ok,
                %{
                  connection: connection,
                  name: :undefined,
                  qos: qos,
                  metadata: metadata,
                  bindings: [],
                  declare_opts: nil,
                  queue: "queue",
                  after_connect: after_connect,
                  consume_options: [no_ack: true, exclusive: false]
                }}
    end

    test "providing connection via a URI" do
      connection = "amqp://guest:guest@127.0.0.1"

      assert {:ok, %{connection: ^connection, queue: "queue"}} =
               AmqpClient.init(queue: "queue", connection: connection)
    end

    test "invalid URI" do
      assert {:error, message} = AmqpClient.init(queue: "queue", connection: "http://example.com")
      assert message =~ "failed parsing AMQP URI"
    end

    test "unsupported options for Broadway" do
      assert {:error, message} = AmqpClient.init(queue: "queue", option_1: 1, option_2: 2)
      assert message =~ "unknown options [:option_1, :option_2], valid options are"
    end

    test "unsupported options for :connection" do
      assert {:error, message} =
               AmqpClient.init(queue: "queue", connection: [option_1: 1, option_2: 2])

      assert message =~ "unknown options [:option_1, :option_2], valid options are"
      assert message =~ "in options [:connection]"
    end

    test "unsupported options for :qos" do
      assert {:error, message} = AmqpClient.init(queue: "queue", qos: [option_1: 1, option_2: 2])
      assert message =~ "unknown options [:option_1, :option_2]"
      assert message =~ "in options [:qos]"
    end

    test "unsupported options for :declare" do
      assert {:error, message} =
               AmqpClient.init(queue: "queue", declare: [option_1: 1, option_2: 2])

      assert message =~ "unknown options [:option_1, :option_2]"
      assert message =~ "in options [:declare]"
    end

    test ":queue is required" do
      assert AmqpClient.init([]) ==
               {:error, "required option :queue not found, received options: []"}

      assert AmqpClient.init(queue: nil) ==
               {:error, "expected :queue to be a string, got: nil"}
    end

    test ":queue should be a string" do
      assert AmqpClient.init(queue: :an_atom) ==
               {:error, "expected :queue to be a string, got: :an_atom"}

      {:ok, config} = AmqpClient.init(queue: "my_queue")
      assert config.queue == "my_queue"
    end

    test ":queue shouldn't be an empty string if :declare is not present" do
      assert AmqpClient.init(queue: "") ==
               {:error,
                "can't use \"\" (server autogenerate) as the queue name without the :declare"}

      assert {:ok, config} = AmqpClient.init(queue: "", declare: [])
      assert config.queue == ""
    end

    test ":metadata should be a list of atoms" do
      {:ok, opts} = AmqpClient.init(queue: "queue", metadata: [:routing_key, :headers])
      assert opts[:metadata] == [:routing_key, :headers]

      message =
        ~s(list element at position 0 in :metadata failed validation: expected "list element" ) <>
          ~s(to be an atom, got: "routing_key")

      assert AmqpClient.init(queue: "queue", metadata: ["routing_key", :headers]) ==
               {:error, message}
    end

    test ":bindings should be a list of tuples" do
      {:ok, opts} = AmqpClient.init(queue: "queue", bindings: [{"my-exchange", [arguments: []]}])
      assert opts[:bindings] == [{"my-exchange", [arguments: []]}]

      message =
        ~s(list element at position 0 in :bindings failed validation: expected binding to be ) <>
          ~s(a {exchange, opts} tuple, got: :something)

      assert AmqpClient.init(queue: "queue", bindings: [:something, :else]) ==
               {:error, message}
    end

    test ":merge_options options should be merged with normal opts" do
      merge_options_fun = fn index -> [queue: "queue#{index}"] end

      assert {:ok, %{queue: "queue4"}} =
               AmqpClient.init(
                 queue: "queue",
                 broadway: [index: 4],
                 merge_options: merge_options_fun
               )
    end

    test ":merge_options doesn't perform deep merging" do
      merge_options_fun = fn index ->
        [connection: [username: "user#{index}"]]
      end

      assert {:ok, %{connection: connection}} =
               AmqpClient.init(
                 queue: "queue",
                 broadway: [index: 4],
                 connection: [host: "example.com"],
                 merge_options: merge_options_fun
               )

      assert connection == [username: "user4"]
    end

    test ":merge_options should be a 1-arity function" do
      assert AmqpClient.init(queue: "queue", merge_options: :wat) ==
               {:error, ":merge_options must be a function with arity 1, got: :wat"}
    end

    test ":merge_options should return a keyword list" do
      assert AmqpClient.init(
               queue: "queue",
               broadway: [index: 4],
               merge_options: fn _index -> :ok end
             ) ==
               {:error, "The :merge_options function should return a keyword list, got: :ok"}
    end

    test "options returned by :merge_options are still validated" do
      merge_options_fun = fn _index -> [option: 1] end

      assert {:error, message} =
               AmqpClient.init(
                 queue: "queue",
                 merge_options: merge_options_fun,
                 broadway: [index: 4]
               )

      assert message =~ "unknown options [:option], valid options are"
    end

    test ":merge_options raises if there's no Broadway index in the options" do
      merge_options_fun = fn _index -> [option: 1] end

      assert_raise RuntimeError, "missing broadway index", fn ->
        AmqpClient.init(
          queue: "queue",
          merge_options: merge_options_fun,
          broadway: []
        )
      end

      assert_raise RuntimeError, "missing broadway index", fn ->
        AmqpClient.init(
          queue: "queue",
          merge_options: merge_options_fun
        )
      end
    end
  end
end
