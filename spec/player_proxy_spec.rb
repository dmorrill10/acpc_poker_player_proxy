require_relative 'support/spec_helper'

require 'acpc_poker_types/player'
require 'acpc_poker_types/match_state'
require 'acpc_poker_basic_proxy'
require 'acpc_poker_types/game_definition'

require 'acpc_dealer'

require 'acpc_poker_player_proxy/player_proxy'

include AcpcPokerTypes
include DealerData
include AcpcPokerBasicProxy
include AcpcPokerPlayerProxy

describe PlayerProxy do
  PORT_NUMBER = 9001
  HOST_NAME = 'localhost'
  DEALER_INFO = AcpcDealer::ConnectionInformation.new PORT_NUMBER, HOST_NAME

  describe '#update!' do
    it 'does not return too early on pre-flop all-in' do
      game_def_file = AcpcDealer::GAME_DEFINITION_FILE_PATHS[2][:nolimit]
      x_states = [
        'MATCHSTATE:0:0:c:JhJs|',
        'MATCHSTATE:0:0:cr20000:JhJs|',
        'MATCHSTATE:0:0:cr20000c///:JhJs|7d2c/7hQsAd/Jd/4c',
        'MATCHSTATE:1:1::|TcQd'
      ].map! { |s| MatchState.parse(s) }
      action = 'r20000'

      @basic_proxy = init_basic_proxy

      states_recieved = []
      states_to_send = x_states.dup
      @basic_proxy.expects(:receive_match_state!).returns(
        states_to_send.shift
      ).once
      patient = PlayerProxy.new(DEALER_INFO, game_def_file, 0)

      states_recieved << patient.match_state

      @basic_proxy.expects(:send_action).once.with(action)

      @basic_proxy.expects(:receive_match_state!).returns(
        states_to_send.shift
      ).once

      patient.play!(action) do |patt|
        @basic_proxy.expects(:receive_match_state!).returns(
          states_to_send.shift
        ).once unless states_to_send.empty?

        states_recieved << patt.match_state
      end

      states_recieved.must_equal x_states
    end
    describe "keeps track of state for a sequence of match states and actions in Doyle's game" do
      it 'in no-limit' do
        # Change this number to do more or less thorough tests.
        # Some interesting three player hands occur after 120
        # Careful though, even 10 hands takes about 7 seconds,
        # and it scales more than linearly
        num_hands = 10
        each_match(num_hands) do |match|
          @match = match
          @match.for_every_seat! do |users_seat|
            @basic_proxy = init_basic_proxy

            @patient = PlayerProxy.new(DEALER_INFO, @match.match_def.game_def, users_seat) do |patt|
              check_players_at_the_table patt

              @match.next_hand! unless @match.hand_number

              if @match.current_hand.final_turn?
                @match.current_hand.end_hand!

                break if @match.final_hand?

                @match.next_hand!
              end
              @match.next_turn!

              @basic_proxy.expects(:receive_match_state!).returns(
                @match.current_hand.current_match_state
              ).once
            end

            while @match.current_hand.last_action do
              @basic_proxy.expects(:send_action).once.with(@match.current_hand.last_action.action.to_acpc)

              @patient.play!(@match.current_hand.last_action.action.to_acpc) do |patt|

                check_players_at_the_table patt

                if @match.current_hand.final_turn?
                  @match.current_hand.end_hand!
                  break if @match.final_hand?
                  @match.next_hand!
                end
                @match.next_turn!

                @basic_proxy.expects(:receive_match_state!).returns(
                  @match.current_hand.current_match_state
                ).once
              end
            end
            @match.hand_number.must_equal(num_hands - 1)
            @match.current_hand.end_hand!
            @match.end_match!
          end
        end
      end
    end
  end
  def each_match(num_hands)
    match_logs.each do |log_description|
      yield PokerMatchData.parse_files(
        log_description.actions_file_path,
        log_description.results_file_path,
        log_description.player_names,
        AcpcDealer::DEALER_DIRECTORY,
        num_hands
      )
    end
  end
  def init_basic_proxy
    @basic_proxy = mock('BasicProxy') { stubs :send_comment }
    BasicProxy.expects(:new).with(DEALER_INFO).returns(@basic_proxy).once
    @basic_proxy
  end

  def check_players_at_the_table(patient)
    patient.player_acting_sequence.must_equal @match.player_acting_sequence
    patient.players.length.must_equal @match.players.length
    check_next_to_act patient
    check_last_turn patient
    patient.player_acting_sequence_string.must_equal @match.player_acting_sequence_string
    patient.users_turn_to_act?.must_equal @match.users_turn_to_act?
    check_betting_sequence patient

    if @match.current_hand
      patient.hand_ended?.must_equal @match.current_hand.final_turn?
      unless @match.current_hand.final_turn?
        patient.match_state.all_hands.each do |hand|
          hand.each do |card|
            card.must_be_kind_of AcpcPokerTypes::Card
          end
        end
      end
    end
    # @todo Test this eventually
    # patient.min_wager.to_i.must_equal @min_wager.to_i
  end

  def check_player_blind_relation(patient)
    patient.position_relative_to_dealer(patient.big_blind_payer).must_equal(
      @match.match_def.game_def.blinds.index(@match.match_def.game_def.blinds.max)
    )
    patient.position_relative_to_dealer(patient.small_blind_payer).must_equal(
      @match.match_def.game_def.blinds.index do |blind|
        blind < @match.match_def.game_def.blinds.max && blind > 0
      end
    )
  end
  def check_betting_sequence(patient)
    x_betting_sequence = @match.betting_sequence.map do |actions|
      actions.map { |action| AcpcPokerTypes::PokerAction.new(action).to_s }
    end

    return x_betting_sequence.flatten.empty?.must_equal(true) unless patient.match_state

    patient.match_state.betting_sequence.map do |actions|
      actions.map { |action| AcpcPokerTypes::PokerAction.new(action).to_s }
    end.must_equal x_betting_sequence

    patient.match_state.betting_sequence_string.scan(/([a-z]\d*|\/)/).flatten.map do |action|
      if action.match(/\//)
        action
      else
        AcpcPokerTypes::PokerAction.new(action).to_s
      end
    end.join('').must_equal @match.betting_sequence_string
  end
  def check_next_to_act(patient)
    if @match.current_hand && @match.current_hand.next_action
      patient.next_player_to_act.seat.must_equal @match.current_hand.next_action.seat
    else
      patient.next_player_to_act.seat.must_be_nil
    end
  end
  def check_last_turn(patient)
    return unless @match.current_hand && @match.current_hand.final_turn?

    patient.players.players_close_enough?(@match.players).must_equal true
    check_player_blind_relation(patient)
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
  def close_enough?(other)
    @seat == other.seat &&
    balance == other.balance
  end
end
