defmodule Depot.Adapter.InMemory do
  @moduledoc """
  Depot Adapter using an `Agent` for in memory storage.

  ## Direct usage

      iex> filesystem = Depot.Adapter.InMemory.configure(name: InMemoryFileSystem)
      iex> start_supervised(filesystem)
      iex> :ok = Depot.write(filesystem, "test.txt", "Hello World")
      iex> {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Usage with a module

      defmodule InMemoryFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemoryFileSystem)

      InMemoryFileSystem.write("test.txt", "Hello World")
      {:ok, "Hello World"} = InMemoryFileSystem.read("test.txt")
  """

  defmodule AgentStream do
    @enforce_keys [:config, :path]
    defstruct config: nil, path: nil, chunk_size: 1024

    defimpl Enumerable do
      def reduce(%{config: config, path: path, chunk_size: chunk_size}, a, b) do
        case Depot.Adapter.InMemory.read(config, path) do
          {:ok, contents} ->
            contents
            |> Depot.chunk(chunk_size)
            |> reduce(a, b)

          _ ->
            {:halted, []}
        end
      end

      def reduce(_list, {:halt, acc}, _fun), do: {:halted, acc}
      def reduce(list, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(list, &1, fun)}
      def reduce([], {:cont, acc}, _fun), do: {:done, acc}
      def reduce([head | tail], {:cont, acc}, fun), do: reduce(tail, fun.(head, acc), fun)

      def count(_), do: {:error, __MODULE__}
      def slice(_), do: {:error, __MODULE__}
      def member?(_, _), do: {:error, __MODULE__}
    end

    defimpl Collectable do
      def into(%{config: config, path: path} = stream) do
        original =
          case Depot.Adapter.InMemory.read(config, path) do
            {:ok, contents} -> contents
            _ -> ""
          end

        fun = fn
          list, {:cont, x} ->
            [x | list]

          list, :done ->
            contents = original <> IO.iodata_to_binary(:lists.reverse(list))
            Depot.Adapter.InMemory.write(config, path, contents)
            stream

          _, :halt ->
            :ok
        end

        {[], fun}
      end
    end
  end

  use Agent

  defmodule Config do
    @moduledoc false
    defstruct name: nil
  end

  @behaviour Depot.Adapter

  @impl Depot.Adapter
  def starts_processes, do: true

  def start_link({__MODULE__, %Config{} = config}) do
    start_link(config)
  end

  def start_link(%Config{} = config) do
    Agent.start_link(fn -> %{} end, name: Depot.Registry.via(__MODULE__, config.name))
  end

  @impl Depot.Adapter
  def configure(opts) do
    config = %Config{
      name: Keyword.fetch!(opts, :name)
    }

    {__MODULE__, config}
  end

  @impl Depot.Adapter
  def write(config, path, contents) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      put_in(state, accessor(path, %{}), IO.iodata_to_binary(contents))
    end)
  end

  @impl Depot.Adapter
  def write_stream(config, path, opts) do
    {:ok,
     %AgentStream{
       config: config,
       path: path,
       chunk_size: Keyword.get(opts, :chunk_size, 1024)
     }}
  end

  @impl Depot.Adapter
  def read(config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        binary when is_binary(binary) -> {:ok, binary}
        _ -> {:error, :enoent}
      end
    end)
  end

  @impl Depot.Adapter
  def read_stream(config, path, opts) do
    {:ok,
     %AgentStream{
       config: config,
       path: path,
       chunk_size: Keyword.get(opts, :chunk_size, 1024)
     }}
  end

  @impl Depot.Adapter
  def delete(%Config{} = config, path) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      {_, state} = pop_in(state, accessor(path))
      state
    end)

    :ok
  end

  @impl Depot.Adapter
  def move(%Config{} = config, source, destination) do
    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(source)) do
        binary when is_binary(binary) ->
          {_, state} =
            state |> put_in(accessor(destination, %{}), binary) |> pop_in(accessor(source))

          {:ok, state}

        _ ->
          {{:error, :enoent}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def copy(%Config{} = config, source, destination) do
    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(source)) do
        binary when is_binary(binary) -> {:ok, put_in(state, accessor(destination, %{}), binary)}
        _ -> {{:error, :enoent}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def copy(%Config{} = _source_config, _source, %Config{} = _destination_config, _destination) do
    {:error, :unsupported}
  end

  @impl Depot.Adapter
  def file_exists(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        binary when is_binary(binary) -> {:ok, :exists}
        _ -> {:ok, :missing}
      end
    end)
  end

  @impl Depot.Adapter
  def list_contents(%Config{} = config, path) do
    contents =
      Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
        paths =
          case get_in(state, accessor(path)) do
            %{} = map -> map
            _ -> %{}
          end

        for {path, x} <- paths do
          case x do
            %{} ->
              %Depot.Stat.Dir{
                name: path,
                size: 0,
                mtime: 0
              }

            bin when is_binary(bin) ->
              %Depot.Stat.File{
                name: path,
                size: byte_size(bin),
                mtime: 0
              }
          end
        end
      end)

    {:ok, contents}
  end

  @impl Depot.Adapter
  def create_directory(%Config{} = config, path) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      put_in(state, accessor(path, %{}), %{})
    end)
  end

  @impl Depot.Adapter
  def delete_directory(%Config{} = config, path, opts) do
    recursive? = Keyword.get(opts, :recursive, false)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case {recursive?, get_in(state, accessor(path))} do
        {_, nil} ->
          {:ok, state}

        {recursive?, map} when is_map(map) and (map_size(map) == 0 or recursive?) ->
          {_, state} = pop_in(state, accessor(path))
          {:ok, state}

        _ ->
          {{:error, :eexist}, state}
      end
    end)
  end

  defp accessor(path, default \\ nil) when is_binary(path) do
    path
    |> Path.absname("/")
    |> Path.split()
    |> do_accessor([], default)
    |> Enum.reverse()
  end

  defp do_accessor([segment], acc, default) do
    [Access.key(segment, default) | acc]
  end

  defp do_accessor([segment | rest], acc, default) do
    do_accessor(rest, [Access.key(segment, %{}) | acc], default)
  end
end
