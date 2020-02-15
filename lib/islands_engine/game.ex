defmodule IslandsEngine.Game do
  use GenServer
  alias IslandsEngine.{Board, Guesses, Rules, Coordinate, Island}

  @players [:player1, :player2]

  def start_link(name) when is_binary(name), do: GenServer.start_link(__MODULE__, name, [])

  @impl true
  def init(name) do
    player1 = %{name: name, board: Board.new(), guesses: Guesses.new()}
    player2 = %{name: nil, board: Board.new(), guesses: Guesses.new()}
    {:ok, %{player1: player1, player2: player2, rules: %Rules{}}}
  end

  @impl true
  def handle_info(:first, state) do
    IO.puts("Handled :first")
    {:noreply, state}
  end

  def add_player(game, name) when is_binary(name) do
    GenServer.call(game, {:add_player, name})
  end

  def position_island(game, player, key, row, col) when player in @players,
    do: GenServer.call(game, {:position_island, player, key, row, col})

  def set_islands(game, player) when player in @players,
    do: GenServer.call(game, {:set_islands, player})

  def guess_coordinate(game, player, row, col), do:
    GenServer.call(game, {:guess_coordinate, player, row, col})



  @impl true
  def handle_call({:add_player, name}, _from, state) do
    with {:ok, rules} <- Rules.check(state.rules, :add_player) do
      state
      |> update_player2_name(name)
      |> update_rules(rules)
      |> reply_success(:ok)
    else
      :error -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:position_island, player, key, row, col}, _from, state) do
    board = player_board(state, player)

    with {:ok, rules} <- Rules.check(state.rules, {:position_islands, player}),
         {:ok, coord} <- Coordinate.new(row, col),
         {:ok, island} <- Island.new(key, coord),
         %{} = board <- Board.position_island(board, key, island) do
      state
      |> update_board(player, board)
      |> update_rules(rules)
      |> reply_success(:ok)
    else
      :error -> {:reply, :error, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:set_islands, player}, _from, state) do
    board = player_board(state, player)

    with {:ok, rules} <- Rules.check(state.rules, {:set_islands, player}),
         true <- Board.all_islands_positioned?(board) do
      state
      |> update_rules(rules)
      |> reply_success(:ok)
    else
      :error -> {:reply, :error, state}
      false -> {:reply, {:error, :all_islands_not_positioned}, state}
    end
  end

  @impl true
  def handle_call({:guess_coordinate, player, row, col}, _from, state) do
    opponent_key = opponent(player)
    opponent_board = player_board(state, opponent_key)

    with {:ok, rules} <- Rules.check(state.rules, {:guess_coordinate, player}),
    {:ok, coord} <- Coordinate.new(row, col),
    {hit_or_miss, forested_island, win_or_not, opponent_board} <- Board.guess(opponent_board, coord),
    {:ok, rules} <- Rules.check(rules, {:win_check, win_or_not}) do
      state
      |> update_board(opponent_key, opponent_board)
      |> update_guesses(player, hit_or_miss, coord)
      |> update_rules(rules)
      |> reply_success({hit_or_miss, forested_island, win_or_not})
    else
      :error -> {:reply, :error, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp update_player2_name(game, name), do: put_in(game.player2.name, name)

  defp update_rules(game, rules), do: %{game | rules: rules}

  defp update_guesses(game, player, hit_or_miss, coord) do
    update_in(game[player].guesses, fn guesses -> Guesses.add(guesses, hit_or_miss, coord) end)
  end

  defp reply_success(state, reply) do
    {:reply, reply, state}
  end

  defp update_board(state, player, board),
    do: Map.update!(state, player, fn player -> %{player | board: board} end)

  # Get the board for an individual player from the game state
  defp player_board(state, player), do: Map.get(state, player).board

  defp opponent(:player1), do: :player2
  defp opponent(:player2), do: :player1
end
