defmodule IslandsEngine.Game do
  use GenServer
  alias IslandsEngine.{Board, Guesses, Rules, Coordinate, Island}

  @players [:player1, :player2]

  @timeout 60 * 60 * 24 * 1000

  ###
  ### Init
  ###

  def via_tuple(name), do: {:via, Registry, {Registry.Game, name}}

  def start_link(name) when is_binary(name),
    do: GenServer.start_link(__MODULE__, name, name: via_tuple(name))

  @impl true
  def init(name) do
    send(self(), {:set_state, name})
    {:ok, fresh_state(name)}
  end

  # Give GameSupervisor the specifications for how to start this GenServer
  def child_spec(name) do
    IO.puts("#{__MODULE__}.child_spec(#{name})")

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [name]},
      restart: :transient
    }
  end

  ###
  ### Client
  ###

  def add_player(game, name) when is_binary(name), do: GenServer.call(game, {:add_player, name})

  def position_island(game, player, key, row, col) when player in @players,
    do: GenServer.call(game, {:position_island, player, key, row, col})

  def set_islands(game, player) when player in @players,
    do: GenServer.call(game, {:set_islands, player})

  def guess_coordinate(game, player, row, col),
    do: GenServer.call(game, {:guess_coordinate, player, row, col})

  ###
  ### Server
  ###

  @impl true
  def handle_info({:set_state, name}, _state) do
    state =
      case :ets.lookup(:game_state, name) do
        [] -> fresh_state(name)
        [{_key, state}] -> state
      end

    :ets.insert(:game_state, {name, state})
    {:noreply, state, @timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    IO.puts("#{__MODULE__} #{state.player1.name} shutting down due timeout")
    {:stop, {:shutdown, :timeout}, state}
  end

  @impl true
  def handle_call({:add_player, name}, _from, state) do
    with {:ok, rules} <- Rules.check(state.rules, :add_player) do
      state
      |> update_player2_name(name)
      |> update_rules(rules)
      |> reply_success(:ok)
    else
      :error -> reply_error(state, :cannot_add_player)
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
      :error -> reply_error(state, :error)
      {:error, reason} -> reply_error(state, reason)
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
      :error -> reply_error(state, :error)
      false -> reply_error(state, {:all_islands_not_positioned})
    end
  end

  @impl true
  def handle_call({:guess_coordinate, player, row, col}, _from, state) do
    opponent_key = opponent(player)
    opponent_board = player_board(state, opponent_key)

    with {:ok, rules} <- Rules.check(state.rules, {:guess_coordinate, player}),
         {:ok, coord} <- Coordinate.new(row, col),
         {hit_or_miss, forested_island, win_or_not, opponent_board} <-
           Board.guess(opponent_board, coord),
         {:ok, rules} <- Rules.check(rules, {:win_check, win_or_not}) do
      state
      |> update_board(opponent_key, opponent_board)
      |> update_guesses(player, hit_or_miss, coord)
      |> update_rules(rules)
      |> reply_success({hit_or_miss, forested_island, win_or_not})
    else
      :error -> reply_error(state, :error)
      {:error, reason} -> reply_error(state, reason)
    end
  end

  @impl true
  def terminate({:shutdown, :timeout}, state) do
    :ets.delete(:game_state, state.player1.name)
    :ok
  end

  def terminate(_, _), do: :ok
  ###
  ### Private
  ###

  defp update_player2_name(game, name), do: put_in(game.player2.name, name)

  defp update_rules(game, rules), do: %{game | rules: rules}

  defp update_guesses(game, player, hit_or_miss, coord) do
    update_in(game[player].guesses, fn guesses -> Guesses.add(guesses, hit_or_miss, coord) end)
  end

  defp reply_success(state, reply) do
    :ets.insert(:game_state, {state.player1.name, state})
    {:reply, reply, state, @timeout}
  end

  # Create a new state on init
  defp fresh_state(name) do
    player1 = %{name: name, board: Board.new(), guesses: Guesses.new()}
    player2 = %{name: nil, board: Board.new(), guesses: Guesses.new()}
    %{player1: player1, player2: player2, rules: %Rules{}}
  end

  defp reply_error(state, reply) do
    IO.puts("#{__MODULE__} Handling error: #{inspect(reply)}")
    {:reply, {:error, reply}, state, @timeout}
  end

  defp update_board(state, player, board),
    do: Map.update!(state, player, fn player -> %{player | board: board} end)

  # Get the board for an individual player from the game state
  defp player_board(state, player), do: Map.get(state, player).board

  defp opponent(:player1), do: :player2
  defp opponent(:player2), do: :player1
end
