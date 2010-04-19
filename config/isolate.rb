# this the default config file used by John Barnette's isolate gem
# you can create a config/isolate_local.rb file to override this
# See the corresponding tasks in Rakefile and GNUmakefile
# `rake isolate' or (faster in the unmodified case, `make isolate')

gem 'rack', '1.1.0'
gem 'unicorn', '0.97.0'

gem 'iobuffer', '0.1.3'
gem 'rev', '0.3.2'

gem 'eventmachine', '0.12.10'

gem 'sinatra', '0.9.4'
gem 'async_sinatra', '0.1.5'

gem 'neverblock', '0.1.6.2'

if defined?(::Fiber)
  gem 'case', '0.5'
  gem 'revactor', '0.1.5'
  gem 'rack-fiber_pool', '0.9.0'
end

gem 'cramp', '0.10'
