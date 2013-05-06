# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "acpc_poker_player_proxy/version"

Gem::Specification.new do |s|
  s.name        = "acpc_poker_player_proxy"
  s.version     = AcpcPokerPlayerProxy::VERSION
  s.authors     = ["Dustin Morrill"]
  s.email       = ["morrill@ualberta.ca"]
  s.homepage    = "https://github.com/dmorrill10/acpc_poker_player_proxy"
  s.summary     = %q{ACPC Poker Player Proxy}
  s.description = %q{A smart proxy for a poker player that connects to the ACPC Dealer and manages match state data}

  s.add_dependency 'acpc_poker_match_state', '~> 0.0'
  s.add_dependency 'acpc_poker_basic_proxy', '~> 0.0'
  s.add_dependency 'acpc_poker_types', '~> 0.0'
  s.add_dependency 'dmorrill10-utils', '~> 1.0'

  s.rubyforge_project = "acpc_poker_player_proxy"

  s.files         = Dir.glob("lib/**/*") + Dir.glob("ext/**/*") + %w(Rakefile acpc_poker_player_proxy.gemspec tasks.rb README.md)
  s.test_files    = Dir.glob "spec/**/*"
  s.require_paths = ["lib"]

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'pry-rescue'
  s.add_development_dependency 'acpc_dealer'
  s.add_development_dependency 'acpc_dealer_data'
end
