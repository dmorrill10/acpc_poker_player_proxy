require_relative 'support/spec_helper'

require 'acpc_poker_types/player'
require 'acpc_poker_basic_proxy'
require 'acpc_poker_types/game_definition'

require 'acpc_dealer'

require 'acpc_poker_player_proxy/player_proxy'

include AcpcPokerTypes
include AcpcDealerData
include AcpcPokerBasicProxy
include CommunicationLogic

describe PlayerProxy do
  PORT_NUMBER = 9001
  HOST_NAME = 'localhost'
  MILLISECOND_RESPONSE_TIMEOUT = 0
  DEALER_INFO = AcpcDealerInformation.new HOST_NAME, PORT_NUMBER, MILLISECOND_RESPONSE_TIMEOUT

  describe '#update!' do
    describe "keeps track of state for a sequence of match states and actions in Doyle's game" do
      it 'in no-limit' do
        @basic_proxy = mock 'BasicProxy'
        BasicProxy.stubs(:new).with(DEALER_INFO).returns(@basic_proxy)

        # Change this number to do more or less thorough tests.
        # Some interesting three player hands occur after 120
        # Careful though, even 10 hands takes about five seconds,
        # and it scales about linearly
        num_hands = 5
        match_logs.each do |log_description|
          @match = PokerMatchData.parse_files(
            log_description.actions_file_path,
            log_description.results_file_path,
            log_description.player_names,
            AcpcDealer::DEALER_DIRECTORY,
            num_hands
          )
          @match.for_every_seat! do |users_seat|
            @match.for_every_hand! do
              @match.current_hand.seat = users_seat

              if @match.hand_number == 0
                @patient = PlayerProxy.new(
                  DEALER_INFO,
                  users_seat,
                  @match.match_def.game_def,
                  @match.players.map { |player| player.name }.join(' '),
                  num_hands
                ) do |patt|
                  # Invalidate hand number for initial check of PATT
                  @match.hand_number = nil unless @match.current_hand.turn_number

                  check_players_at_the_table patt

                  # Resume proper hand iteration
                  @match.hand_number = 0 unless @match.hand_number

                  # Iterate over turns
                  if @match.current_hand.turn_number
                    @match.current_hand.turn_number += 1
                  else
                    @match.current_hand.turn_number = 0
                  end

                  unless @match.current_hand.next_action.seat == users_seat
                    @basic_proxy.stubs(:receive_match_state!).returns(
                      @match.current_hand.current_match_state
                    )
                  end
                end
              end

              while @match.current_hand.turn_number < @match.current_hand.data.length
                @basic_proxy.expects(:send_action).once.given(
                  @match.current_hand.next_action.state,
                  @match.current_hand.next_action.action.to_acpc
                )
                @basic_proxy.stubs(:receive_match_state!).returns(
                  @match.current_hand.current_match_state
                )
                @patient.play! @match.current_hand.next_action.action.to_acpc do |patt|
                  check_players_at_the_table patt

                  @match.current_hand.turn_number += 1
                  unless @match.current_hand.next_action.seat == users_seat
                    @basic_proxy.stubs(:receive_match_state!).returns(
                      @match.current_hand.current_match_state
                    )
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  # def check_turns_of_given_type!(seat, type, data_by_type)
  #   @hand_num = 0
  #   @users_seat = seat.to_i - 1

  #   turns = data_by_type[:actions]

  #   init_before_first_turn_data! @number_of_players, type

  #   init_game_def! type, @players
  #   GameDefinition.stubs(:new).with(@game_def).returns(@game_def)

  #   @basic_proxy = mock 'BasicProxy'
  #   BasicProxy.stubs(:new).with(DEALER_INFO).returns(@basic_proxy)

  #   Player.stubs(:create_players).with(
  #     @players.map{|p| p.name}, @game_def
  #   ).returns(@players)

  #   @expected_players_at_the_table = PlayersAtTheTable.seat_players(
  #     @game_def, @players.map{|p| p.name}, @users_seat, GAME_DEFS[type][:number_of_hands]
  #   )

  #   players_for_patient = create_players type, @number_of_players

  #   Player.stubs(:create_players).with(
  #     players_for_patient.map{|p| p.name}, @game_def
  #   ).returns(players_for_patient)

  #   i = 0
  #   @patient = PlayerProxy.new(
  #     DEALER_INFO,
  #     @users_seat,
  #     @game_def,
  #     (@players.map{ |player| player.name }).join(' '),
  #     GAME_DEFS[type][:number_of_hands]
  #   ) do |players_at_the_table|
  #     check_players_at_the_table players_at_the_table

  #     unless players_at_the_table.users_turn_to_act? || players_at_the_table.match_ended?
  #       i = check_turn! i, turns, seat, type, data_by_type
  #     end
  #   end

  #   # @todo match ended won't be restricted once data is separated better by game def
  #   while (i < turns.length) && !@match_ended
  #     i = check_turn! i, turns, seat, type, data_by_type
  #   end
  # end
  # def check_turn!(i, turns, seat, type, data_by_type)
  #   return i+1 if @match_ended

  #   turn = turns[i]
  #   next_turn = turns[i + 1]
  #   from_player_message = turn[:from_players]
  #   match_state = turn[:to_players][seat]
  #   prev_round = if @last_match_state then @last_match_state.round else nil end

  #   @last_hand = ((GAME_DEFS[type][:number_of_hands] - 1) == @hand_num)

  #   @next_player_to_act = if index_of_next_player_to_act(next_turn) < 0
  #     nil
  #   else
  #     @players[index_of_next_player_to_act(next_turn)]
  #   end
  #   @users_turn_to_act = if @next_player_to_act
  #     @next_player_to_act.seat == @users_seat
  #   else
  #     false
  #   end

  #   @last_match_state = MatchState.parse match_state

  #   @hole_card_hands = order_by_seat_from_dealer_relative @last_match_state.list_of_hole_card_hands,
  #     @last_match_state.position_relative_to_dealer

  #   if @last_match_state.first_state_of_first_round?
  #     init_new_hand_data! type
  #   else
  #     init_new_turn_data! type, from_player_message, prev_round
  #   end

  #   if @last_match_state.round != prev_round || @last_match_state.first_state_of_first_round?
  #     @player_acting_sequence << []
  #     @betting_sequence << []
  #   end

  #   if !next_turn || MatchState.parse(next_turn[:to_players]['1']).first_state_of_first_round?
  #     init_hand_result_data! data_by_type
  #   end

  #   @expected_players_at_the_table.update! @last_match_state

  #   init_after_update_data! type

  #   @basic_proxy.expects(:receive_match_state!).returns(@last_match_state)

  #   return i+1 if from_player_message.empty?

  #   seat_taking_action = from_player_message.keys.first

  #   return i+1 unless seat_taking_action == seat

  #   action = PokerAction.new from_player_message[seat_taking_action]

  #   @basic_proxy.expects(:send_action).with(action)

  #   i += 1
  #   @patient.play!(action) do |players_at_the_table|
  #     check_players_at_the_table players_at_the_table

  #     i = check_turn! i, turns, seat, type, data_by_type
  #   end

  #   i
  # end


  # def init_after_update_data!(type)
  #   @active_players = @players.select { |player| player.active? }
  #   @non_folded_players = @players.select { |player| !player.folded? }
  #   @opponents_cards_visible = @opponents.any? { |player| !player.hole_cards.empty? }
  #   @reached_showdown = @opponents_cards_visible
  #   @less_than_two_non_folded_players = @non_folded_players.length < 2
  #   @hand_ended = @less_than_two_non_folded_players || @reached_showdown
  #   @match_ended = @hand_ended && @last_hand
  #   @player_with_dealer_button = nil
  #   @players.each_index do |j|
  #     if positions_relative_to_dealer[j] == @players.length - 1
  #       @player_with_dealer_button = @players[j]
  #     end
  #   end
  #   @player_blind_relation = @players.inject({}) do |hash, player|
  #     hash[player] = GAME_DEFS[type][:blinds][positions_relative_to_dealer[player.seat]]
  #     hash
  #   end
  # end
  # def init_hand_result_data!(data_by_type)
  #   result = data_by_type[:results][@hand_num]
  #   @hand_num += 1

  #   result.each do |player_name, final_balance|
  #     # @todo This assumption isn't robust yet
  #     player = @players.find { |p| p.name == player_name }

  #     # @todo Only in Doyle's game
  #     @chip_stacks[player.seat] =
  #       @game_def.chip_stacks[positions_relative_to_dealer[player.seat]].to_r +
  #       final_balance.to_r

  #     # @todo Assumes Doyle's game in three player
  #     if final_balance.to_r == 0
  #       @chip_balances[player.seat] = @last_hands_balance[player.seat].to_r
  #       @chip_contributions[player.seat] << -@chip_contributions[player.seat].sum
  #     elsif final_balance.to_r > 0
  #       @chip_balances[player.seat] = @last_hands_balance[player.seat].to_r + final_balance.to_r
  #       @chip_contributions[player.seat] << -@chip_contributions.mapped_sum.sum
  #     end

  #     @last_hands_balance[player.seat] = @chip_balances[player.seat]
  #   end
  # end
  # def init_new_turn_data!(type, from_player_message, prev_round)
  #   @betting_sequence << [] if @betting_sequence.empty?
  #   @player_acting_sequence << [] if @player_acting_sequence.empty?

  #   seat_taking_action = from_player_message.keys.first
  #   seat_of_last_player_to_act = seat_taking_action.to_i - 1
  #   @player_who_acted_last = @players[seat_of_last_player_to_act]

  #   @last_action = PokerAction.new(
  #     from_player_message[seat_taking_action], {
  #       amount_to_put_in_pot: @expected_players_at_the_table.cost_of_action(
  #         @player_who_acted_last,
  #         PokerAction.new(from_player_message[seat_taking_action]), (
  #           @betting_sequence.length - 1
  #         )
  #       ),
  #       acting_player_sees_wager: (
  #         @expected_players_at_the_table.amount_to_call(@player_who_acted_last) > 0 || (
  #           GAME_DEFS[type][:blinds][positions_relative_to_dealer[seat_of_last_player_to_act]] > 0 && (
  #             @player_who_acted_last.actions_taken_this_hand[0].length < 1
  #           )
  #         )
  #       )
  #     }
  #   )

  #   @chip_contributions[seat_of_last_player_to_act][-1] += @last_action.amount_to_put_in_pot.to_r
  #   @chip_stacks[seat_of_last_player_to_act] -= @last_action.amount_to_put_in_pot
  #   @chip_balances[seat_of_last_player_to_act] -= @last_action.amount_to_put_in_pot.to_r

  #   @player_acting_sequence.last << seat_of_last_player_to_act
  #   @player_acting_sequence_string += seat_of_last_player_to_act.to_s
  #   @betting_sequence.last << @last_action
  #   @betting_sequence_string += @last_action.to_acpc

  #   if @last_match_state.round != prev_round
  #     @player_acting_sequence_string += '/'
  #     @betting_sequence_string += '/'
  #     @chip_contributions.each do |contribution|
  #       contribution << 0
  #     end
  #   end
  # end
  # def init_new_hand_data!(type)
  #   @player_who_acted_last = nil

  #   @player_acting_sequence = []
  #   @player_acting_sequence_string = ''

  #   @betting_sequence = []
  #   @betting_sequence_string = ''

  #   init_new_hand_chip_data! type
  # end
  # def init_new_hand_chip_data!(type)
  #   # @todo Assumes Doyle's Game
  #   @chip_stacks = @players.each_index.inject([]) { |stacks, j| stacks << GAME_DEFS[type][:stack_size] }
  #   @chip_contributions = []
  #   @chip_stacks.each_index do |j|
  #     @chip_stacks[j] -= GAME_DEFS[type][:blinds][positions_relative_to_dealer[j]]
  #     @chip_balances[j] -= GAME_DEFS[type][:blinds][positions_relative_to_dealer[j]].to_r
  #     @chip_contributions << [GAME_DEFS[type][:blinds][positions_relative_to_dealer[j]].to_r]
  #   end
  # end
  # def init_before_first_turn_data!(num_players, type)
  #   @last_hands_balance = num_players.times.inject([]) { |balances, i| balances << 0 }
  #   @players = create_players(type, num_players)
  #   @chip_balances = @players.map { |player| player.chip_balance.to_r }
  #   @chip_contributions = @players.map { |player| player.chip_contributions }
  #   @user_player = @players[@users_seat]
  #   @opponents = @players.select { |player| !player.eql?(@user_player) }
  #   @hole_card_hands = @players.inject([]) { |hands, player| hands << player.hole_cards }
  #   @opponents_cards_visible = false
  #   @reached_showdown = @opponents_cards_visible
  #   @less_than_two_non_folded_players = false
  #   @hand_ended = @less_than_two_non_folded_players || @reached_showdown
  #   @last_hand = false
  #   @match_ended = @hand_ended && @last_hand
  #   @active_players = @players
  #   @non_folded_players = @players
  #   @player_acting_sequence = [[]]
  #   @player_acting_sequence_string = ''
  #   @users_turn_to_act = false
  #   @chip_stacks = @players.map { |player| player.chip_stack }
  #   @betting_sequence = [[]]
  #   @betting_sequence_string = ''
  #   @player_who_acted_last = nil
  #   @next_player_to_act = nil
  #   @player_with_dealer_button = nil
  #   @player_blind_relation = nil
  # end
  # def index_of_next_player_to_act(turn) turn[:from_players].keys.first.to_r - 1 end
  # def positions_relative_to_dealer
  #   positions = []
  #   @last_match_state.list_of_hole_card_hands.each_index do |pos_rel_dealer|
  #     @hole_card_hands.each_index do |seat|
  #       if @hole_card_hands[seat] == @last_match_state.list_of_hole_card_hands[pos_rel_dealer]
  #         positions[seat] = pos_rel_dealer
  #       end
  #     end
  #     @last_match_state.list_of_hole_card_hands
  #   end
  #   positions
  # end
  # def order_by_seat_from_dealer_relative(list_of_hole_card_hands,
  #                                        users_pos_rel_to_dealer)
  #   new_list = [].fill Hand.new, (0..list_of_hole_card_hands.length - 1)
  #   list_of_hole_card_hands.each_index do |pos_rel_dealer|
  #     position_difference = pos_rel_dealer - users_pos_rel_to_dealer
  #     seat = (position_difference + @users_seat) % list_of_hole_card_hands.length
  #     new_list[seat] = list_of_hole_card_hands[pos_rel_dealer]
  #   end

  #   new_list
  # end
  # def create_players(type, num_players)
  #   num_players.times.inject([]) do |players, i|
  #     name = "p#{i + 1}"
  #     player_seat = i
  #     players << Player.join_match(name, player_seat, GAME_DEFS[type][:stack_size])
  #   end
  # end
  # def init_game_def!(type, players)
  #   @game_def = mock 'GameDefinition'
  #   @game_def.stubs(:first_player_positions).returns(GAME_DEFS[type][:first_player_positions])
  #   @game_def.stubs(:number_of_players).returns(players.length)
  #   @game_def.stubs(:blinds).returns(GAME_DEFS[type][:blinds])
  #   @game_def.stubs(:chip_stacks).returns(players.map { |player| player.chip_stack })
  #   @game_def.stubs(:min_wagers).returns(GAME_DEFS[type][:small_bets])
  #   @game_def
  # end


# @todo ????
  def check_patient(patient=@patient)
    check_players_at_the_table patient.players_at_the_table
  end
  def check_players_at_the_table(patient)
    patient.player_acting_sequence.must_equal @match.player_acting_sequence
    patient.number_of_players.must_equal @match.players.length
    check_last_action patient
    check_next_to_act patient
    check_last_turn patient
    patient.opponents_cards_visible?.must_equal @match.opponents_cards_visible?
    patient.reached_showdown?.must_equal @match.opponents_cards_visible?
    patient.less_than_two_non_folded_players?.must_equal @match.non_folded_players.length < 2

    if @match.current_hand
      patient.hand_ended?.must_equal @match.current_hand.final_turn?
      patient.match_ended?.must_equal (@match.final_hand? && @match.current_hand.final_turn?)
    end
    patient.last_hand?.must_equal (
      if @match.final_hand?.nil?
        false
      else
        @match.final_hand?
      end
    )
    patient.player_acting_sequence_string.must_equal @match.player_acting_sequence_string
    patient.users_turn_to_act?.must_equal @match.users_turn_to_act?
    check_betting_sequence patient
    # @todo Test this eventually
    # patient.min_wager.to_i.must_equal @min_wager.to_i
  end
  def check_player_blind_relation(patient)
    expected_player_blind_relation = @match.player_blind_relation
    patient.player_blind_relation.each do |player, blind|
      expected_player_and_blind = expected_player_blind_relation.to_a.find do |player_and_blind|
        player_and_blind.first.seat == player.seat
      end

      expected_player = expected_player_and_blind.first
      expected_blind = expected_player_and_blind.last

      player.close_enough?(expected_player).must_equal true
      blind.must_equal expected_blind
    end
  end
  def check_betting_sequence(patient)
    patient_betting_sequence = patient.betting_sequence.map do |actions|
        actions.map { |action| PokerAction.new(action.to_s).to_s }
    end
    expected_betting_sequence = @match.betting_sequence.map do |actions|
      actions.map { |action| action.to_s }
    end
    patient_betting_sequence.must_equal expected_betting_sequence

    patient.betting_sequence_string.scan(/([a-z]\d*|\/)/).flatten.map do |action|
      if action.match(/\//)
        action
      else
        PokerAction.new(action).to_s
      end
    end.join('').must_equal @match.betting_sequence_string
  end
  def check_last_action(patient)
    if @match.current_hand && @match.current_hand.last_action
      patient.player_who_acted_last.seat.must_equal @match.current_hand.last_action.seat
    else
      patient.player_who_acted_last.must_be_nil
    end
  end
  def check_next_to_act(patient)
    if @match.current_hand && @match.current_hand.next_action
      patient.next_player_to_act.seat.must_equal @match.current_hand.next_action.seat
    else
      patient.next_player_to_act.must_be_nil
    end
  end
  def check_last_turn(patient)
    return unless @match.current_hand && @match.current_hand.final_turn?
    patient.players.players_close_enough?(@match.players).must_equal true
    patient.user_player.close_enough?(@match.player).must_equal true
    patient.opponents.players_close_enough?(@match.opponents).must_equal true
    patient.non_folded_players.players_close_enough?(@match.non_folded_players).must_equal true
    patient.active_players.players_close_enough?(@match.active_players).must_equal true
    patient.player_with_dealer_button.close_enough?(@match.player_with_dealer_button).must_equal true
    check_player_blind_relation patient
    patient.chip_stacks.must_equal @match.chip_stacks
    patient.chip_balances.must_equal @match.chip_balances
    patient.chip_contributions.sum.must_equal @match.chip_contributions.sum
  end
end

class Array
  def players_close_enough?(other_players)
    return false if other_players.length != length
    each_with_index do |player, index|
      return false unless player.close_enough?(other_players[index])
    end
    true
  end
  def reject_empty_elements
    reject do |elem|
      elem.empty?
    end
  end
end

class AcpcPokerTypes::Player
  def acpc_actions_taken_this_hand
    acpc_actions = @actions_taken_this_hand.map do |actions_per_turn|
      actions_per_turn.map { |action| AcpcPokerTypes::PokerAction.new(action).to_s }
    end
    if acpc_actions.first.empty?
      acpc_actions
    else
      acpc_actions.reject_empty_elements
    end
  end

  def close_enough?(other)
    @name == other.name &&
    @seat == other.seat &&
    @chip_stack == other.chip_stack &&
    @chip_balance == other.chip_balance &&
    acpc_actions_taken_this_hand == other.acpc_actions_taken_this_hand
  end
end