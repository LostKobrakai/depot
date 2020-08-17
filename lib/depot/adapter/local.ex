defmodule Depot.Adapter.Local do
  @moduledoc """
  Depot Adapter for the local filesystem.

  ## Direct usage

      iex> {:ok, prefix} = Briefly.create(directory: true)
      iex> filesystem = Depot.Adapter.Local.configure(prefix: prefix)
      iex> :ok = Depot.write(filesystem, "test.txt", "Hello World")
      iex> {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Usage with a module

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      LocalFileSystem.write("test.txt", "Hello World")
      {:ok, "Hello World"} = LocalFileSystem.read("test.txt")

  ## Usage with Streams

  The following options are available for streams:

    * `:chunk_size` - When reading, the amount to read,
      by `:line` (default) or by a given number of bytes.

    * `:modes` - A list of modes to use when opening the file
      for reading. For more information, see the docs for
      `File.stream!/3`.

  ### Examples

      {:ok, %File.Stream{}} = Depot.read_stream(filesystem, "test.txt")

      # with custom read chunk size
      {:ok, %File.Stream{line_or_bytes: 1_024, ...}} = Depot.read_stream(filesystem, "test.txt", chunk_size: 1_024)

      # with custom file read modes
      {:ok, %File.Stream{mode: [{:encoding, :utf8}, :binary], ...}} = Depot.read_stream(filesystem, "test.txt", modes: [encoding: :utf8])

  """
  use Bitwise, only_operators: true
  alias Depot.Visibility.PortableUnixVisibilityConverter, as: DefaultVisibilityConverter

  defmodule Config do
    @moduledoc false

    @type t :: %__MODULE__{
            prefix: Path.t(),
            converter: Depot.Visibility.UnixVisibilityConverter.t(),
            visibility: Depot.Visibility.PortableUnixVisibilityConverter.Config.t()
          }

    defstruct prefix: nil, converter: nil, visibility: nil
  end

  @behaviour Depot.Adapter

  @impl Depot.Adapter
  def starts_processes, do: false

  @impl Depot.Adapter
  def configure(opts) do
    visibility_config = Keyword.get(opts, :visibility, [])
    converter = Keyword.get(visibility_config, :converter, DefaultVisibilityConverter)
    visibility = visibility_config |> Keyword.drop([:converter]) |> converter.config()

    config = %Config{
      prefix: Keyword.fetch!(opts, :prefix),
      converter: converter,
      visibility: visibility
    }

    {__MODULE__, config}
  end

  @impl Depot.Adapter
  def write(%Config{} = config, path, contents, opts) do
    path = full_path(config, path)

    with :ok <- ensure_directory(config, Path.dirname(path), opts),
         :ok <- File.write(path, contents),
         :ok <- maybe_set_visibility(config, path, opts) do
      :ok
    end
  end

  @impl Depot.Adapter
  def write_stream(%Config{} = config, path, opts) do
    modes = opts[:modes] || []
    line_or_bytes = opts[:chunk_size] || :line
    {:ok, File.stream!(full_path(config, path), modes, line_or_bytes)}
  rescue
    e -> {:error, e}
  end

  @impl Depot.Adapter
  def read(%Config{} = config, path) do
    File.read(full_path(config, path))
  end

  @impl Depot.Adapter
  def read_stream(%Config{} = config, path, opts) do
    modes = opts[:modes] || []
    line_or_bytes = opts[:chunk_size] || :line
    {:ok, File.stream!(full_path(config, path), modes, line_or_bytes)}
  rescue
    e -> {:error, e}
  end

  @impl Depot.Adapter
  def delete(%Config{} = config, path) do
    with {:error, :enoent} <- File.rm(full_path(config, path)), do: :ok
  end

  @impl Depot.Adapter
  def move(%Config{} = config, source, destination, opts) do
    source = full_path(config, source)
    destination = full_path(config, destination)

    with :ok <- ensure_directory(config, Path.dirname(destination), opts) do
      File.rename(source, destination)
    end
  end

  @impl Depot.Adapter
  def copy(%Config{} = config, source, destination, opts) do
    source = full_path(config, source)
    destination = full_path(config, destination)

    with :ok <- ensure_directory(config, Path.dirname(destination), opts) do
      File.cp(source, destination)
    end
  end

  @impl Depot.Adapter
  def copy(
        %Config{} = source_config,
        source,
        %Config{} = destination_config,
        destination,
        opts
      ) do
    source = full_path(source_config, source)
    destination = full_path(destination_config, destination)

    with :ok <- ensure_directory(destination_config, Path.dirname(destination), opts) do
      File.cp(source, destination)
    end
  end

  @impl Depot.Adapter
  def file_exists(%Config{} = config, path) do
    case File.exists?(full_path(config, path)) do
      true -> {:ok, :exists}
      false -> {:ok, :missing}
    end
  end

  @impl Depot.Adapter
  def list_contents(%Config{} = config, path) do
    path = full_path(config, path)

    with {:ok, files} <- File.ls(path) do
      contents =
        for file <- files,
            {:ok, stat} = File.stat(Path.join(path, file), time: :posix),
            stat.type in [:directory, :regular] do
          case stat.type do
            :directory -> %Depot.Stat.Dir{name: file, size: stat.size, mtime: stat.mtime}
            :regular -> %Depot.Stat.File{name: file, size: stat.size, mtime: stat.mtime}
          end
        end

      {:ok, contents}
    end
  end

  @impl Depot.Adapter
  def create_directory(%Config{} = config, path, opts) do
    path = full_path(config, path)
    ensure_directory(config, path, opts)
  end

  @impl Depot.Adapter
  def delete_directory(%Config{} = config, path, opts) do
    path = full_path(config, path)

    if Keyword.get(opts, :recursive, false) do
      with {:ok, _} <- File.rm_rf(path), do: :ok
    else
      File.rmdir(path)
    end
  end

  @impl Depot.Adapter
  def clear(%Config{} = config) do
    with {:ok, contents} <- list_contents(%Config{} = config, ".") do
      Enum.reduce_while(contents, :ok, fn dir_or_file, :ok ->
        case clear_dir_or_file(config, dir_or_file) do
          :ok -> {:cont, :ok}
          err -> {:halt, err}
        end
      end)
    end
  end

  @impl Depot.Adapter
  def set_visibility(%Config{} = config, path, visibility) do
    path = full_path(config, path)

    mode =
      if File.dir?(path) do
        config.converter.for_directory(config.visibility, visibility)
      else
        config.converter.for_file(config.visibility, visibility)
      end

    File.chmod(path, mode)
  end

  @impl Depot.Adapter
  def visibility(%Config{} = config, path) do
    path = full_path(config, path)

    with {:ok, %{mode: mode, type: type}} <- File.stat(path) do
      mode = mode &&& 0o777

      visibility =
        case type do
          :directory ->
            config.converter.from_directory(config.visibility, mode)

          _ ->
            config.converter.from_file(config.visibility, mode)
        end

      {:ok, visibility}
    end
  end

  defp clear_dir_or_file(config, %Depot.Stat.Dir{name: dir}),
    do: delete_directory(config, dir, recursive: true)

  defp clear_dir_or_file(config, %Depot.Stat.File{name: name}),
    do: delete(config, name)

  defp full_path(config, path) do
    Depot.RelativePath.join_prefix(config.prefix, path)
  end

  defp maybe_set_visibility(config, path, opts) do
    case Keyword.fetch(opts, :visibility) do
      {:ok, visibility} ->
        mode = config.converter.for_file(config.visibility, visibility)
        File.chmod(path, mode)

      _ ->
        :ok
    end
  end

  defp ensure_directory(config, path, opts) do
    mode =
      case Keyword.fetch(opts, :directory_visibility) do
        {:ok, visibility} -> config.converter.for_directory(config.visibility, visibility)
        _ -> false
      end

    do_mkdir_p(IO.chardata_to_string(path), mode)
  end

  defp do_mkdir_p("/", _) do
    :ok
  end

  defp do_mkdir_p(path, mode) do
    if File.dir?(path) do
      :ok
    else
      parent = Path.dirname(path)

      if parent == path do
        # Protect against infinite loop
        {:error, :einval}
      else
        _ = do_mkdir_p(parent, mode)

        case :file.make_dir(path) do
          {:error, :eexist} = error ->
            if File.dir?(path), do: :ok, else: error

          :ok ->
            if mode do
              File.chmod(path, mode)
            else
              :ok
            end

          other ->
            other
        end
      end
    end
  end
end
