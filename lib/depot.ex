defmodule Depot do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @type adapter :: module()
  @type filesystem :: {module(), Depot.Adapter.config()}

  @doc """
  Write to a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.write(filesystem, "test.txt", "Hello World")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.write("test.txt", "Hello World")

  """
  @spec write(filesystem, Path.t(), iodata(), keyword()) :: :ok | {:error, term}
  def write({adapter, config}, path, contents, opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.write(config, path, contents, opts)
    end
  end

  @doc """
  Returns a `Stream` for writing to the given `path`.

  ## Options

  The following stream options apply to all adapters:

    * `:chunk_size` - When reading, the amount to read,
      usually expressed as a number of bytes.

  ## Examples

  > Note: The shape of the returned stream will
  > necessarily depend on the adapter in use. In the
  > following examples the [`Local`](`Depot.Adapter.Local`)
  > adapter is invoked, which returns a `File.Stream`.

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, %File.Stream{}} = Depot.write_stream(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, %File.Stream{}} = LocalFileSystem.write_stream("test.txt")

  """
  def write_stream({adapter, config}, path, opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.write_stream(config, path, opts)
    end
  end

  @doc """
  Read from a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, "Hello World"} = LocalFileSystem.read("test.txt")

  """
  @spec read(filesystem, Path.t(), keyword()) :: {:ok, binary} | {:error, term}
  def read({adapter, config}, path, _opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.read(config, path)
    end
  end

  @doc """
  Returns a `Stream` for reading the given `path`.

  ## Options

  The following stream options apply to all adapters:

    * `:chunk_size` - When reading, the amount to read,
      usually expressed as a number of bytes.

  ## Examples

  > Note: The shape of the returned stream will
  > necessarily depend on the adapter in use. In the
  > following examples the [`Local`](`Depot.Adapter.Local`)
  > adapter is invoked, which returns a `File.Stream`.

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, %File.Stream{}} = Depot.read_stream(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, %File.Stream{}} = LocalFileSystem.read_stream("test.txt")

  """
  def read_stream({adapter, config}, path, opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.read_stream(config, path, opts)
    end
  end

  @doc """
  Delete a file from a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.delete(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.delete("test.txt")

  """
  @spec delete(filesystem, Path.t(), keyword()) :: :ok | {:error, term}
  def delete({adapter, config}, path, _opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.delete(config, path)
    end
  end

  @doc """
  Move a file from source to destination on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.move(filesystem, "test.txt", "other-test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.move("test.txt", "other-test.txt")

  """
  @spec move(filesystem, Path.t(), Path.t(), keyword()) :: :ok | {:error, term}
  def move({adapter, config}, source, destination, opts \\ []) do
    with {:ok, source} <- Depot.RelativePath.normalize(source),
         {:ok, destination} <- Depot.RelativePath.normalize(destination) do
      adapter.move(config, source, destination, opts)
    end
  end

  @doc """
  Copy a file from source to destination on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.copy(filesystem, "test.txt", "other-test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.copy("test.txt", "other-test.txt")

  """
  @spec copy(filesystem, Path.t(), Path.t(), keyword()) :: :ok | {:error, term}
  def copy({adapter, config}, source, destination, opts \\ []) do
    with {:ok, source} <- Depot.RelativePath.normalize(source),
         {:ok, destination} <- Depot.RelativePath.normalize(destination) do
      adapter.copy(config, source, destination, opts)
    end
  end

  @doc """
  Copy a file from source to destination on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.copy(filesystem, "test.txt", "other-test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.copy("test.txt", "other-test.txt")

  """
  @spec file_exists(filesystem, Path.t(), keyword()) :: {:ok, :exists | :missing} | {:error, term}
  def file_exists({adapter, config}, path, _opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.file_exists(config, path)
    end
  end

  @doc """
  List the contents of a folder on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, contents} = Depot.list_contents(filesystem, ".")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, contents} = LocalFileSystem.list_contents(".")

  """
  @spec list_contents(filesystem, Path.t(), keyword()) ::
          {:ok, [%Depot.Stat.Dir{} | %Depot.Stat.File{}]} | {:error, term}
  def list_contents({adapter, config}, path, _opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.list_contents(config, path)
    end
  end

  @doc """
  Create a directory

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.create_directory(filesystem, "test/")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.create_directory("test/")

  """
  @spec create_directory(filesystem, Path.t(), keyword()) :: :ok | {:error, term}
  def create_directory({adapter, config}, path, opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path),
         {:ok, path} <- Depot.RelativePath.assert_directory(path) do
      adapter.create_directory(config, path, opts)
    end
  end

  @doc """
  Delete a directory.

  ## Options

    * `:recursive` - Recursively delete contents. Defaults to `false`.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.delete_directory(filesystem, "test/")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.delete_directory("test/")

  """
  @spec delete_directory(filesystem, Path.t(), keyword()) :: :ok | {:error, term}
  def delete_directory({adapter, config}, path, opts \\ []) do
    with {:ok, path} <- Depot.RelativePath.normalize(path),
         {:ok, path} <- Depot.RelativePath.assert_directory(path) do
      adapter.delete_directory(config, path, opts)
    end
  end

  @doc """
  Clear the filesystem.

  This is always recursive.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.clear(filesystem)

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.clear()

  """
  @spec clear(filesystem, keyword()) :: :ok | {:error, term}
  def clear({adapter, config}, _opts \\ []) do
    adapter.clear(config)
  end

  @spec set_visibility(filesystem, Path.t(), Depot.Visibility.t()) :: :ok | {:error, term}
  def set_visibility({adapter, config}, path, visibility) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.set_visibility(config, path, visibility)
    end
  end

  @spec visibility(filesystem, Path.t()) :: {:ok, Depot.Visibility.t()} | {:error, term}
  def visibility({adapter, config}, path) do
    with {:ok, path} <- Depot.RelativePath.normalize(path) do
      adapter.visibility(config, path)
    end
  end

  @doc """
  Copy a file from one filesystem to the other

  This can either be done natively if the same adapter is used for both filesystems
  or by streaming/read-write cycle the file from the source to the local system
  and back to the destination.

  ## Examples

  ### Direct filesystem

      filesystem_source = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      filesystem_destination = Depot.Adapter.Local.configure(prefix: "/home/user/storage2")
      :ok = Depot.copy_between_filesystem({filesystem_source, "test.txt"}, {filesystem_destination, "copy.txt"})

  ### Module-based filesystem

      defmodule LocalSourceFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      defmodule LocalDestinationFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage2"
      end

      :ok = Depot.copy_between_filesystem(
        {LocalSourceFileSystem.__filesystem__(), "test.txt"},
        {LocalDestinationFileSystem.__filesystem__(), "copy.txt"}
      )

  """
  @spec copy_between_filesystem(
          source :: {filesystem, Path.t()},
          destination :: {filesystem, Path.t()},
          keyword()
        ) :: :ok | {:error, term}
  def copy_between_filesystem(source, destination, opts \\ [])

  # Same adapter, same config -> just do a plain copy
  def copy_between_filesystem({filesystem, source}, {filesystem, destination}, opts) do
    copy(filesystem, source, destination, opts)
  end

  # Same adapter -> try direct copy if supported
  def copy_between_filesystem(
        {{adapter, config_source}, path_source} = source,
        {{adapter, config_destination}, path_destination} = destination,
        opts
      ) do
    with :ok <- adapter.copy(config_source, path_source, config_destination, path_destination) do
      :ok
    else
      {:error, :unsupported} -> copy_via_local_memory(source, destination, opts)
      error -> error
    end
  end

  # different adapter
  def copy_between_filesystem(source, destination, opts) do
    copy_via_local_memory(source, destination, opts)
  end

  defp copy_via_local_memory(
         {{source_adapter, _} = source_filesystem, source_path},
         {{destination_adapter, _} = destination_filesystem, destination_path},
         opts
       ) do
    case {Depot.read_stream(source_filesystem, source_path, opts),
          Depot.write_stream(destination_filesystem, destination_path, opts)} do
      # A and B support streaming -> Stream data
      {{:ok, read_stream}, {:ok, write_stream}} ->
        read_stream
        |> Stream.into(write_stream)
        |> Stream.run()

      # Only A support streaming -> Stream to memory and write when done
      {{:ok, read_stream}, {:error, ^destination_adapter}} ->
        Depot.write(destination_filesystem, destination_path, Enum.into(read_stream, []))

      # Only B support streaming -> Load into memory and stream to B
      {{:error, ^source_adapter}, {:ok, write_stream}} ->
        with {:ok, contents} <- Depot.read(source_filesystem, source_path) do
          contents
          |> chunk(Keyword.get(opts, :chunk_size, 5 * 1024))
          |> Enum.into(write_stream)
        end

      # Neither support streaming
      {{:error, ^source_adapter}, {:error, ^destination_adapter}} ->
        with {:ok, contents} <- Depot.read(source_filesystem, source_path) do
          Depot.write(destination_filesystem, destination_path, contents)
        end
    end
  rescue
    e -> {:error, e}
  end

  @doc false
  # Also used by the InMemory adapter and therefore not private
  def chunk("", _size), do: []

  def chunk(binary, size) when byte_size(binary) >= size do
    {chunk, rest} = :erlang.split_binary(binary, size)
    [chunk | chunk(rest, size)]
  end

  def chunk(binary, _size), do: [binary]
end
