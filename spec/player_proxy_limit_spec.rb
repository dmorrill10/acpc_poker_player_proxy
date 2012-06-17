
require File.expand_path('../support/spec_helper', __FILE__)

require 'acpc_poker_types/player'
require 'acpc_poker_basic_proxy/basic_proxy'
require 'acpc_poker_types/game_definition'

require File.expand_path('../support/dealer_data', __FILE__)

require File.expand_path('../../lib/acpc_poker_player_proxy/player_proxy', __FILE__)

describe PlayerProxy do
  include DealerData

  # @todo integrate this into the data where its collected
  GAME_DEFS = {
    limit: {
      stack_size: 400, small_bets: [2, 2, 4, 4],
      first_player_positions: [1, 0, 0, 0],
      blinds: [2, 1],
      number_of_hands: 100
    },
    nolimit: {
      stack_size: 20000, small_bets: [100, 100, 100, 100],
      first_player_positions: [1, 0, 0, 0],
      blinds: [100, 50],
      number_of_hands: 100
    }
  }

  PORT_NUMBER = 9001
  HOST_NAME = 'localhost'
  MILLISECOND_RESPONSE_TIMEOUT = 0
  DEALER_INFO = AcpcDealerInformation.new HOST_NAME, PORT_NUMBER, MILLISECOND_RESPONSE_TIMEOUT

  describe '#update!' do
    describe "keeps track of state for a sequence of match states and actions in Doyle's game" do
      it 'in limit' do
        # @todo Move into data retrieval method
        DealerData::DATA.each do |num_players, data_by_num_players|
          @number_of_players = num_players
          ((0..(num_players-1)).map{ |i| (i+1).to_s }).each do |seat|
            data_by_num_players.each do |type, data_by_type|
              next unless type == :limit

              check_turns_of_given_type! seat, type, data_by_type
            end
          end
        end
      end
    end
  end

  def check_turns_of_given_type!(seat, type, data_by_type)
    @hand_num = 0
    @users_seat = seat.to_i - 1

    turns = data_by_type[:actions]

    init_before_first_turn_data! @number_of_players, type

    init_game_def! type, @players
    GameDefinition.stubs(:new).with(@game_def).returns(@game_def)

    @basic_proxy = mock 'BasicProxy'
    BasicProxy.stubs(:new).with(DEALER_INFO).returns(@basic_proxy)

    Player.stubs(:create_players).with(
      @players.map{|p| p.name}, @game_def
    ).returns(@players)

    @expected_players_at_the_table = PlayersAtTheTable.seat_players(
      @game_def, @players.map{|p| p.name}, @users_seat, GAME_DEFS[type][:number_of_hands]
    )

    players_for_patient = create_players type, @number_of_players

    Player.stubs(:create_players).with(
      players_for_patient.map{|p| p.name}, @game_def
    ).returns(players_for_patient)

    i = 0
    @patient = PlayerProxy.new(
      DEALER_INFO,
      @users_seat,
      @game_def,
      (@players.map{ |player| player.name }).join(' '),
      GAME_DEFS[type][:number_of_hands]
    ) do |players_at_the_table|
      check_players_at_the_table players_at_the_table

      unless players_at_the_table.users_turn_to_act? || players_at_the_table.match_ended?
        i = check_turn! i, turns, seat, type, data_by_type
      end
    end

    # @todo match ended won't be restricted once data is separated better by game def
    while (i < turns.length) && !@match_ended
      i = check_turn! i, turns, seat, type, data_by_type
    end
  end
  def check_turn!(i, turns, seat, type, data_by_type)
    return i+1 if @match_ended

    turn = turns[i]
    next_turn = turns[i + 1]
    from_player_message = turn[:from_players]
    match_state = turn[:to_players][seat]
    prev_round = if @last_match_state then @last_match_state.round else nil end

    @last_hand = ((GAME_DEFS[type][:number_of_hands] - 1) == @hand_num)

    @next_player_to_act = if index_of_next_player_to_act(next_turn) < 0
      nil
    else
      @players[index_of_next_player_to_act(next_turn)]
    end
    @users_turn_to_act = if @next_player_to_act
      @next_player_to_act.seat == @users_seat
    else
      false
    end

    @last_match_state = MatchState.parse match_state

    @hole_card_hands = order_by_seat_from_dealer_relative @last_match_state.list_of_hole_card_hands,
      @last_match_state.position_relative_to_dealer

    if @last_match_state.first_state_of_first_round?
      init_new_hand_data! type
    else
      init_new_turn_data! type, from_player_message, prev_round
    end

    if @last_match_state.round != prev_round || @last_match_state.first_state_of_first_round?
      @player_acting_sequence << []
      @betting_sequence << []
    end

    if !next_turn || MatchState.parse(next_turn[:to_players]['1']).first_state_of_first_round?
      init_hand_result_data! data_by_type
    end

    @expected_players_at_the_table.update! @last_match_state

    init_after_update_data! type

    @basic_proxy.expects(:receive_match_state!).returns(@last_match_state)

    return i+1 if from_player_message.empty?

    seat_taking_action = from_player_message.keys.first

    return i+1 unless seat_taking_action == seat

    action = PokerAction.new from_player_message[seat_taking_action]

    @basic_proxy.expects(:send_action).with(action)

    i += 1
    @patient.play!(action) do |players_at_the_table|
      check_players_at_the_table players_at_the_table

      i = check_turn! i, turns, seat, type, data_by_type
    end

    i
  end


  def init_after_update_data!(type)
    @active_players = @players.select { |player| player.active? }
    @non_folded_players = @players.select { |player| !player.folded? }
    @opponents_cards_visible = @opponents.any? { |player| !player.hole_cards.empty? }
    @reached_showdown = @opponents_cards_visible
    @less_than_two_non_folded_players = @non_folded_players.length < 2
    @hand_ended = @less_than_two_non_folded_players || @reached_showdown
    @match_ended = @hand_ended && @last_hand
    @player_with_dealer_button = nil
    @players.each_index do |j|
      if positions_relative_to_dealer[j] == @players.length - 1
        @player_with_dealer_button = @players[j]
      end
    end
    @player_blind_relation = @players.inject({}) do |hash, player|
      hash[player] = GAME_DEFS[type][:blinds][positions_relative_to_dealer[player.seat]]
      hash
    end
  end
  def init_hand_result_data!(data_by_type)
    result = data_by_type[:results][@hand_num]
    @hand_num += 1

    result.each do |player_name, final_balance|
      # @todo This assumption isn't robust yet
      player = @players.find { |p| p.name == player_name }

      # @todo Only in Doyle's game
      @chip_stacks[player.seat] =
        @game_def.chip_stacks[positions_relative_to_dealer[player.seat]].to_i +
        final_balance.to_i

      # @todo Assumes Doyle's game in three player
      if final_balance.to_i == 0
        @chip_balances[player.seat] = @last_hands_balance[player.seat].to_i
        @chip_contributions[player.seat] << -@chip_contributions[player.seat].sum
      elsif final_balance.to_i > 0
        @chip_balances[player.seat] = @last_hands_balance[player.seat].to_i + final_balance.to_i
        @chip_contributions[player.seat] << -@chip_contributions.mapped_sum.sum
      end

      @last_hands_balance[player.seat] = @chip_balances[player.seat]
    end
  end
  def init_new_turn_data!(type, from_player_message, prev_round)
    @betting_sequence << [] if @betting_sequence.empty?
    @player_acting_sequence << [] if @player_acting_sequence.empty?

    seat_taking_action = from_player_message.keys.first
    seat_of_last_player_to_act = seat_taking_action.to_i - 1
    @player_who_acted_last = @players[seat_of_last_player_to_act]

    @last_action = PokerAction.new(
      from_player_message[seat_taking_action], {
        amount_to_put_in_pot: @expected_players_at_the_table.cost_of_action(
          @player_who_acted_last,
          PokerAction.new(from_player_message[seat_taking_action]), (
            @betting_sequence.length - 1
          )
        ),
        acting_player_sees_wager: (
          @expected_players_at_the_table.amount_to_call(@player_who_acted_last) > 0 || (
            GAME_DEFS[type][:blinds][positions_relative_to_dealer[seat_of_last_player_to_act]] > 0 && (
              @player_who_acted_last.actions_taken_this_hand[0].length < 1
            )
          )
        )
      }
    )

    @chip_contributions[seat_of_last_player_to_act][-1] += @last_action.amount_to_put_in_pot.to_i
    @chip_stacks[seat_of_last_player_to_act] -= @last_action.amount_to_put_in_pot
    @chip_balances[seat_of_last_player_to_act] -= @last_action.amount_to_put_in_pot.to_i

    @player_acting_sequence.last << seat_of_last_player_to_act
    @player_acting_sequence_string += seat_of_last_player_to_act.to_s
    @betting_sequence.last << @last_action
    @betting_sequence_string += @last_action.to_acpc

    if @last_match_state.round != prev_round
      @player_acting_sequence_string += '/'
      @betting_sequence_string += '/'
      @chip_contributions.each do |contribution|
        contribution << 0
      end
    end
  end
  def init_new_hand_data!(type)
    @player_who_acted_last = nil

    @player_acting_sequence = []
    @player_acting_sequence_string = ''

    @betting_sequence = []
    @betting_sequence_string = ''

    init_new_hand_chip_data! type
  end
  def init_new_hand_chip_data!(type)
    # @todo Assumes Doyle's Game
    @chip_stacks = @players.each_index.inject([]) { |stacks, j| stacks << GAME_DEFS[type][:stack_size] }
    @chip_contributions = []
    @chip_stacks.each_index do |j|
      @chip_stacks[j] -= GAME_DEFS[type][:blinds][positions_relative_to_dealer[j]]
      @chip_balances[j] -= GAME_DEFS[type][:blinds][positions_relative_to_dealer[j]].to_i
      @chip_contributions << [GAME_DEFS[type][:blinds][positions_relative_to_dealer[j]].to_i]
    end
  end
  def init_before_first_turn_data!(num_players, type)
    @last_hands_balance = num_players.times.inject([]) { |balances, i| balances << 0 }
    @players = create_players(type, num_players)
    @chip_balances = @players.map { |player| player.chip_balance.to_i }
    @chip_contributions = @players.map { |player| player.chip_contributions }
    @user_player = @players[@users_seat]
    @opponents = @players.select { |player| !player.eql?(@user_player) }
    @hole_card_hands = @players.inject([]) { |hands, player| hands << player.hole_cards }
    @opponents_cards_visible = false
    @reached_showdown = @opponents_cards_visible
    @less_than_two_non_folded_players = false
    @hand_ended = @less_than_two_non_folded_players || @reached_showdown
    @last_hand = false
    @match_ended = @hand_ended && @last_hand
    @active_players = @players
    @non_folded_players = @players
    @player_acting_sequence = [[]]
    @player_acting_sequence_string = ''
    @users_turn_to_act = false
    @chip_stacks = @players.map { |player| player.chip_stack }
    @betting_sequence = [[]]
    @betting_sequence_string = ''
    @player_who_acted_last = nil
    @next_player_to_act = nil
    @player_with_dealer_button = nil
    @player_blind_relation = nil
  end
  def index_of_next_player_to_act(turn) turn[:from_players].keys.first.to_i - 1 end
  def positions_relative_to_dealer
    positions = []
    @last_match_state.list_of_hole_card_hands.each_index do |pos_rel_dealer|
      @hole_card_hands.each_index do |seat|
        if @hole_card_hands[seat] == @last_match_state.list_of_hole_card_hands[pos_rel_dealer]
          positions[seat] = pos_rel_dealer
        end
      end
      @last_match_state.list_of_hole_card_hands
    end
    positions
  end
  def order_by_seat_from_dealer_relative(list_of_hole_card_hands,
                                         users_pos_rel_to_dealer)
    new_list = [].fill Hand.new, (0..list_of_hole_card_hands.length - 1)
    list_of_hole_card_hands.each_index do |pos_rel_dealer|
      position_difference = pos_rel_dealer - users_pos_rel_to_dealer
      seat = (position_difference + @users_seat) % list_of_hole_card_hands.length
      new_list[seat] = list_of_hole_card_hands[pos_rel_dealer]
    end

    new_list
  end
  def create_players(type, num_players)
    num_players.times.inject([]) do |players, i|
      name = "p#{i + 1}"
      player_seat = i
      players << Player.join_match(name, player_seat, GAME_DEFS[type][:stack_size])
    end
  end
  def init_game_def!(type, players)
    @game_def = mock 'GameDefinition'
    @game_def.stubs(:first_player_positions).returns(GAME_DEFS[type][:first_player_positions])
    @game_def.stubs(:number_of_players).returns(players.length)
    @game_def.stubs(:blinds).returns(GAME_DEFS[type][:blinds])
    @game_def.stubs(:chip_stacks).returns(players.map { |player| player.chip_stack })
    @game_def.stubs(:min_wagers).returns(GAME_DEFS[type][:small_bets])
    @game_def
  end
  def check_patient
    check_players_at_the_table @patient.players_at_the_table
  end
  def check_players_at_the_table(players_at_the_table)
    players_at_the_table.player_acting_sequence.should == @player_acting_sequence
    players_at_the_table.number_of_players.should == @number_of_players
    (players_at_the_table.players.map { |player| player.hole_cards }).should == @hole_card_hands
    players_at_the_table.opponents_cards_visible?.should == @opponents_cards_visible
    players_at_the_table.reached_showdown?.should == @reached_showdown
    players_at_the_table.less_than_two_non_folded_players?.should == @less_than_two_non_folded_players
    players_at_the_table.hand_ended?.should == @hand_ended
    players_at_the_table.last_hand?.should == @last_hand
    players_at_the_table.match_ended?.should == @match_ended
    players_at_the_table.player_acting_sequence_string.should == @player_acting_sequence_string
    players_at_the_table.users_turn_to_act?.should == @users_turn_to_act
    players_at_the_table.chip_stacks.should == @chip_stacks
    players_at_the_table.chip_balances.should == @chip_balances
    players_at_the_table.betting_sequence.should == @betting_sequence
    players_at_the_table.betting_sequence_string.should == @betting_sequence_string
    players_at_the_table.chip_contributions.should == @chip_contributions
  end
end
