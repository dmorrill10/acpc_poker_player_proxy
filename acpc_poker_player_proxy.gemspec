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

  s.add_dependency 'acpc_poker_match_state', '~> 2.0'
  s.add_dependency 'acpc_poker_basic_proxy', '~> 3.0'
  s.add_dependency 'acpc_poker_types', '~> 5.0'
  s.add_dependency 'contextual_exceptions', '~> 0.0'
  s.add_dependency 'methadone', '~> 1.2'
  s.add_dependency 'acpc_dealer', '~> 1.0'

  s.rubyforge_project = "acpc_poker_player_proxy"

  s.files         = `git ls-files`.split($\)
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_development_dependency 'turn', '~> 0.9'
  s.add_development_dependency 'minitest', '~> 4.7'
  s.add_development_dependency 'awesome_print', '~> 1.0'
  s.add_development_dependency 'pry-rescue', '~> 1.0'
  s.add_development_dependency 'simplecov', '~> 0.7'
  s.add_development_dependency 'mocha', '~> 0.13'
end
