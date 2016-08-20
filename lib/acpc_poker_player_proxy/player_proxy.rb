require 'delegate'

require 'acpc_poker_types/players_at_the_table'
require 'acpc_poker_types/player'
require 'acpc_poker_types/game_definition'
require 'acpc_poker_basic_proxy/basic_proxy'

require 'contextual_exceptions'
using ContextualExceptions::ClassRefinement

module AcpcPokerPlayerProxy

class PlayerProxy < DelegateClass(AcpcPokerTypes::PlayersAtTheTable)
  include AcpcPokerTypes
  include AcpcPokerBasicProxy

  exceptions :match_ended

  # @return [PlayersAtTheTable] Summary of the progression of the match
  #  in which, this player is participating, since this object's instantiation.
  attr_reader :players_at_the_table

  attr_reader :match_has_ended

  attr_reader :game_def

  attr_reader :must_send_ready

  # @param [DealerInformation] dealer_information Information about the dealer to which this bot should connect.
  # @param [GameDefinition, #to_s] game_definition_argument A game definition; either a +GameDefinition+ or the name of the file containing a game definition.

  def initialize(
    dealer_information,
    game_definition_argument,
    users_seat = nil,
    must_send_ready = false
  )
    @must_send_ready = must_send_ready
    game_def = if game_definition_argument.kind_of?(
      GameDefinition
    )
      game_definition_argument
    else
      GameDefinition.parse_file(game_definition_argument)
    end
    @basic_proxy = BasicProxy.new dealer_information

    @players_at_the_table = if users_seat
      PlayersAtTheTable.seat_players game_def, users_seat
    else
      PlayersAtTheTable.seat_players game_def
    end

    @match_has_ended = false

    yield @players_at_the_table if block_given?

    update_match_state_if_necessary! do |players_at_the_table|
      yield players_at_the_table if block_given?
    end

    super @players_at_the_table
  end

  # Player action interface
  # @param [PokerAction] action The action to take.
  def play!(action)
    begin
      @basic_proxy.send_action action
    rescue AcpcPokerBasicProxy::DealerStream::UnableToWriteToDealer => e
      raise MatchEnded.with_context(
        "Cannot take action #{action} because the match has ended!",
        e
      )
    end

    update_match_state! do |players_at_the_table|
      __setobj__ @players_at_the_table = players_at_the_table

      yield @players_at_the_table if block_given?
    end
  end

  def match_ended?
    @match_has_ended
  end

  def next_hand!
    begin
      @basic_proxy.send_ready
    rescue AcpcPokerBasicProxy::DealerStream::UnableToWriteToDealer => e
      raise MatchEnded.with_context(
        "Cannot take action #{action} because the match has ended!",
        e
      )
    end

    update_match_state! do |players_at_the_table|
      __setobj__ @players_at_the_table = players_at_the_table

      yield @players_at_the_table if block_given?
    end
  end

  private

  def update_match_state_if_necessary!
    return self if (
      @players_at_the_table.users_turn_to_act? ||
      match_ended? ||
      (@must_send_ready && @players_at_the_table.hand_ended?)
    )

    update_match_state! do |players_at_the_table|
      yield players_at_the_table if block_given?
    end
  end

  def update_match_state!
    begin
      yield @players_at_the_table.update!(@basic_proxy.receive_match_state!) if block_given?
    rescue AcpcPokerBasicProxy::DealerStream::UnableToGetFromDealer
      @match_has_ended = true
    end

    update_match_state_if_necessary! do |players_at_the_table|
      yield players_at_the_table if block_given?
    end
  end
end
end
