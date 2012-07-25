
require 'simplecov'
SimpleCov.start

require 'mocha'

RSpec.configure do |config|
  # == Mock Framework
  config.mock_with :mocha
end


require 'ruby-prof'

RSpec.configure do |config|
  config.before(:all) do
    unless $started
      $started = true
      puts "start profiler for #{described_class}"

      RubyProf.measure_mode = RubyProf::MEMORY

      RubyProf.start
    end
  end
  config.after(:all) do
    if $started
      puts "stop profiler for #{described_class}"
      $started = nil
      FileUtils.mkdir_p File.expand_path("../../profiled_specs", __FILE__)

      result = RubyProf.stop

      File.open File.expand_path("../../profiled_specs/#{described_class}.html", __FILE__), 'w' do |file|
        RubyProf::GraphHtmlPrinter.new(result).print(file, min_percent: (ENV['MIN_PERCENT'] || 0.1).to_f)
      end
    end
  end
end
