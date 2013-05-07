
require 'dmorrill10-utils'

require 'acpc_poker_match_state/players_at_the_table'
require 'acpc_poker_types/player'
require 'acpc_poker_types/game_definition'
require 'acpc_poker_basic_proxy/basic_proxy'

class PlayerProxy
  include AcpcPokerTypes
  include AcpcPokerMatchState
  include AcpcPokerBasicProxy

  exceptions :match_ended

  # @return [PlayersAtTheTable] Summary of the progression of the match
  #  in which, this player is participating, since this object's instantiation.
  attr_reader :players_at_the_table

  attr_reader :game_def

  attr_reader :users_seat

  attr_reader :player_names

  attr_reader :number_of_hands

  # @param [DealerInformation] dealer_information Information about the dealer to which this bot should connect.
  # @param [GameDefinition, #to_s] game_definition_argument A game definition; either a +GameDefinition+ or the name of the file containing a game definition.
  # @param [String] player_names The names of the players in this match.
  # @param [Integer] number_of_hands The number of hands in this match.
  def initialize(
    dealer_information,
    users_seat,
    game_definition_argument,
    player_names='user p2',
    number_of_hands=1
  )
    @game_def = if game_definition_argument.kind_of?(
      GameDefinition
    )
      game_definition_argument
    else
      GameDefinition.new(game_definition_argument)
    end
    @basic_proxy = BasicProxy.new dealer_information

    @player_names = player_names.split(/,?\s+/)

    @users_seat = users_seat

    @number_of_hands = number_of_hands

    @players_at_the_table = create_players_at_the_table

    yield @players_at_the_table if block_given?

    update_match_state_if_necessary! do |players_at_the_table|
      yield players_at_the_table if block_given?
    end
  end

  # Player action interface
  # @param [PokerAction] action The action to take.
  def play!(action)
    if @players_at_the_table.match_ended?
      raise MatchEnded, "Cannot take action #{action} because the match has ended!"
    end

    @basic_proxy.send_action action

    update_match_state! do |players_at_the_table|
      yield @players_at_the_table = players_at_the_table
    end
  end

  private

  def update_match_state_if_necessary!
    unless @players_at_the_table.users_turn_to_act? || @players_at_the_table.match_ended?
      update_match_state! do |players_at_the_table|
        yield players_at_the_table
      end
    end
  end

  def update_match_state!
    @players_at_the_table.update!(@basic_proxy.receive_match_state!)

    yield @players_at_the_table

    update_match_state_if_necessary! do |players_at_the_table|
      yield players_at_the_table
    end
  end

  def create_players_at_the_table
    PlayersAtTheTable.seat_players(
      @game_def,
      @player_names,
      @users_seat,
      @number_of_hands
    )
  end
end
