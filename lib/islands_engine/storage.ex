defmodule IslandsEngine.Storage do
  @dir "./persist/"
  @path "./persist/game_state.toml"

  def init() do
    File.mkdir_p(@dir)

    if not File.exists?(@path) do
      File.write(@path, "")
    end
  end

  def lookup(key) do
    with {:ok, yaml} <- yaml(),
         {:ok, value} <- yaml[String.to_atom(key)] do
      {key, value}
    else
      {:error, _reason} -> []
      nil -> []
    end
  end

  def insert(key, state) do
    IO.puts("#{__MODULE__}.insert(#{key}, ...)")
    with {:ok, yaml} <- yaml() do
      new_yaml =
        case lookup(key) do
          [] ->
            [{key, state} | yaml]

          {:ok, _val} ->
            [{key, state} | yaml]
            # Map.update(yaml, key, state, fn state -> state end)
        end
      IO.puts "New YAML:"
      IO.inspect(new_yaml)
      contents = :fast_yaml.encode(new_yaml)
      write(contents)
      IO.puts "Contents:"
      IO.inspect(contents)
    else
      error -> IO.inspect(error)
    end
  end

  def delete(key), do: :ok

  defp yaml do
    case :fast_yaml.decode_from_file(@path, [{:plain_as_atom, true}]) do
      {:ok, []} -> {:ok, %{}}
      {:ok, [yaml]} -> {:ok, yaml}
    end
  end

  defp write(content), do: File.write(@path, content)
end
