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
            Depot.Adapter.InMemory.write(config, path, contents, [])
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
    Agent.start_link(fn -> {%{}, %{}} end, name: Depot.Registry.via(__MODULE__, config.name))
  end

  @impl Depot.Adapter
  def configure(opts) do
    config = %Config{
      name: Keyword.fetch!(opts, :name)
    }

    {__MODULE__, config}
  end

  @impl Depot.Adapter
  def write(config, path, contents, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      file = {IO.iodata_to_binary(contents), %{visibility: visibility}}
      directory = {%{}, %{visibility: directory_visibility}}
      put_in(state, accessor(path, directory), file)
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
        {binary, _meta} when is_binary(binary) -> {:ok, binary}
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
  def move(%Config{} = config, source, destination, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(source)) do
        {binary, _meta} when is_binary(binary) ->
          file = {binary, %{visibility: visibility}}
          directory = {%{}, %{visibility: directory_visibility}}

          {_, state} =
            state |> put_in(accessor(destination, directory), file) |> pop_in(accessor(source))

          {:ok, state}

        _ ->
          {{:error, :enoent}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def copy(%Config{} = config, source, destination, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(source)) do
        {binary, _meta} when is_binary(binary) ->
          file = {binary, %{visibility: visibility}}
          directory = {%{}, %{visibility: directory_visibility}}
          {:ok, put_in(state, accessor(destination, directory), file)}

        _ ->
          {{:error, :enoent}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def copy(
        %Config{} = _source_config,
        _source,
        %Config{} = _destination_config,
        _destination,
        _opts
      ) do
    {:error, :unsupported}
  end

  @impl Depot.Adapter
  def file_exists(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {binary, _meta} when is_binary(binary) -> {:ok, :exists}
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
            {%{} = map, _meta} -> map
            _ -> %{}
          end

        for {path, x} <- paths do
          case x do
            {%{}, _meta} ->
              %Depot.Stat.Dir{
                name: path,
                size: 0,
                mtime: 0
              }

            {bin, _meta} when is_binary(bin) ->
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
  def create_directory(%Config{} = config, path, opts) do
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)
    directory = {%{}, %{visibility: directory_visibility}}

    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      put_in(state, accessor(path, directory), directory)
    end)
  end

  @impl Depot.Adapter
  def delete_directory(%Config{} = config, path, opts) do
    recursive? = Keyword.get(opts, :recursive, false)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case {recursive?, get_in(state, accessor(path))} do
        {_, nil} ->
          {:ok, state}

        {recursive?, {map, _meta}} when is_map(map) and (map_size(map) == 0 or recursive?) ->
          {_, state} = pop_in(state, accessor(path))
          {:ok, state}

        _ ->
          {{:error, :eexist}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def clear(%Config{} = config) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn _ -> {%{}, %{}} end)
  end

  @impl Depot.Adapter
  def set_visibility(%Config{} = config, path, visibility) do
    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {_, _} ->
          state =
            update_in(state, accessor(path), fn {contents, meta} ->
              {contents, Map.put(meta, :visibility, visibility)}
            end)

          {:ok, state}

        _ ->
          {{:error, :enoent}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def visibility(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {_, %{visibility: visibility}} -> {:ok, visibility}
        _ -> {:error, :enoent}
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
    [Access.key(segment, default), Access.elem(0) | acc]
  end

  defp do_accessor([segment | rest], acc, default) do
    intermediate_default = default || {%{}, %{}}
    do_accessor(rest, [Access.key(segment, intermediate_default), Access.elem(0) | acc], default)
  end
end
