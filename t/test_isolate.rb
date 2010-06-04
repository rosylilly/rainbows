require 'rubygems'
require 'isolate'

path = "tmp/isolate/ruby-#{RUBY_VERSION}"
opts = {
  :system => false,
  # we want "ruby-1.8.7" and not "ruby-1.8", so disable multiruby
  :multiruby => false,
  :path => path,
}

old_out = $stdout.dup
$stdout.reopen($stderr)

Isolate.now!(opts) do
  gem 'rack', '1.1.0'
  gem 'unicorn', '0.99.0'

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

  gem 'cramp', '0.11'
end

$stdout.reopen(old_out)
puts Dir["#{path}/gems/*-*/lib"].map { |x| File.expand_path(x) }.join(':')
