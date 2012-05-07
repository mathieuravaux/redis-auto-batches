require "redis-auto-batches"
require "redis"
require "pry"

Dir[File.expand_path("../support/**/*.rb", __FILE__)].each do |f|
  require f
end


RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus
end
