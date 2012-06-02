
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
   attr_reader :players_at_the_table
      
   attr_reader :game_def
   
   attr_reader :users_seat
   
   attr_reader :player_names
   
   attr_reader :number_of_hands
   
   # @param [DealerInformation] dealer_information Information about the dealer to which this bot should connect.
   # @param [GameDefinition, #to_s] game_definition_argument A game definition; either a +GameDefinition+ or the name of the file containing a game definition.
   # @param [String] player_names The names of the players in this match.
   # @param [Integer] number_of_hands The number of hands in this match.
   def initialize(dealer_information, users_seat, game_definition_argument,
                  player_names='user p2', number_of_hands=1)
      @game_def = if game_definition_argument.kind_of?(GameDefinition)
         game_definition_argument
      else
         GameDefinition.new(game_definition_argument)
      end
      @basic_proxy = BasicProxy.new dealer_information      
      
      @player_names = player_names.split(/,?\s+/)
      
      @users_seat = users_seat
      
      @number_of_hands = number_of_hands
      
      @players_at_the_table = create_players_at_the_table
      
      yield @players_at_the_table
      
      
      unless @players_at_the_table.users_turn_to_act? || @players_at_the_table.match_ended?
         update_match_state! do |players_at_the_table|
            yield players_at_the_table
         end
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
         yield players_at_the_table
      end
   end
   
   def pop_player_state!
      @players_at_the_table_snapshots.pop
   end
   
   private
   
   def update_match_state!
      puts "pas: #{@players_at_the_table.player_acting_sequence}"
      
      match_state = @basic_proxy.receive_match_state_string!
      @players_at_the_table.update!(match_state)
      
      puts "pas: #{@players_at_the_table.player_acting_sequence}"
      puts "update_match_state!: match_state: #{match_state}"
      
      yield @players_at_the_table
      
      while !(@players_at_the_table.users_turn_to_act? || @players_at_the_table.match_ended?)
         match_state = @basic_proxy.receive_match_state_string!
         @players_at_the_table.update!(match_state)
         
         puts "update_match_state!: match_state: #{match_state}"
         
         yield @players_at_the_table
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
