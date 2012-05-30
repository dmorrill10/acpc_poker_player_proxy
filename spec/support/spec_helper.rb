
require 'simplecov'
SimpleCov.start

require 'mocha'

require File.expand_path('../test_example', __FILE__)

RSpec.configure do |config|
   # == Mock Framework
   config.mock_with :mocha
end
