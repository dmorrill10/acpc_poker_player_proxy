
# @todo Make a good system for copying PATT instances 


# Gems
require 'acpc_poker_types/types/player'
require 'acpc_poker_types/acpc_poker_types_defs'
require 'acpc_poker_types/mixins/utils'

require 'acpc_poker_basic_proxy/basic_proxy'

require 'acpc_poker_match_state/players_at_the_table'

# Local mixins
require File.expand_path('../mixins/array_mixin', __FILE__)

# A proxy player for the web poker application.
class PlayerProxy
   include AcpcPokerTypesDefs
   
   exceptions :match_ended
   
   # @return [Array<PlayersAtTheTable>] Summary of the progression of the match
   #  in which, this player is participating, since this object's instantiation.
   attr_reader :match_snapshots
   
   # @param [DealerInformation] dealer_information Information about the dealer to which this bot should connect.
   # @param [GameDefinition, #to_s] game_definition_argument A game definition; either a +GameDefinition+ or the name of the file containing a game definition.
   # @param [String] player_names The names of the players in this match.
   # @param [Integer] number_of_hands The number of hands in this match.
   def initialize(dealer_information, users_seat, game_definition_argument,
                  player_names='user p2', number_of_hands=1)
      game_definition = if game_definition_argument.kind_of?(GameDefinition)
         game_definition_argument
      else
         GameDefinition.new(game_definition_argument)
      end
      @basic_proxy = BasicProxy.new dealer_information
      @match_snapshots = [PlayersAtTheTable.seat_players(
                           Player.create_players(player_names.split(/,?\s+/), game_definition),
                           users_seat,
                           game_definition,
                           number_of_hands
                          )
                         ]
      
      update_match_state! unless @match_snapshots.last.users_turn_to_act?
   end
   
   # Player action interface
   # @param [PokerAction] action The action to take.
   def play!(action)
      raise MatchEnded, "Cannot take action #{action} because the match has ended!" if match_ended?
      
      @basic_proxy.send_action action
      
      update_match_state!
   end
   
   # @see MatchState#match_ended?
   def match_ended?      
      current_match_state.match_ended?
   end
      
   private
   
   def current_match_state
      @match_snapshots.last
   end
   
   def take_match_snapshot
      #first_match_state = @match_snapshots.first
      #match_state = PlayerProxy.new(first_match_state.game_definition,
      #                             first_match_state.match_state_string,
      #                             first_match_state.player_names,
      #                             first_match_state.number_of_hands)      
      #@match_snapshots.rest.each do |previous_match_states|
      #   match_state.update! previous_match_states.match_state_string
      #end
      #match_state
   end
   
   def update_match_state!
      next_match_state = take_match_snapshot.update!(next_match_state_string)
      @match_snapshots << next_match_state
      update_match_state! unless (users_turn_to_act? or match_ended?)
   end
   
   def next_match_state_string
      # @todo This BasicProxy method should have an ! at the end, since it changes its current_match_state
      if @match_snapshots
         @basic_proxy.receive_match_state_string @match_snapshots.last.acting_player_sees_wager?
      else
         @basic_proxy.receive_match_state_string
      end
   end 
   
   # @see MatchState#users_turn_to_act?
   def users_turn_to_act?
      current_match_state.users_turn_to_act?
   end
end
