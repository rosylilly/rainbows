# -*- encoding: binary -*-

# This module adds \Rainbows! to the
# {Unicorn::Configurator}[http://unicorn.bogomips.org/Unicorn/Configurator.html]
module Rainbows::Configurator
  Unicorn::Configurator::DEFAULTS.merge!({
    :use => Rainbows::Base,
    :worker_connections => 50,
    :keepalive_timeout => 5,
    :keepalive_requests => 100,
    :client_max_body_size => 1024 * 1024,
    :client_header_buffer_size => 1024,
  })

  # configures \Rainbows! with a given concurrency model to +use+ and
  # a +worker_connections+ upper-bound.  This method may be called
  # inside a Unicorn/\Rainbows! configuration file:
  #
  #   Rainbows! do
  #     use :ThreadSpawn # concurrency model to use
  #     worker_connections 400
  #     keepalive_timeout 0 # zero disables keepalives entirely
  #     client_max_body_size 5*1024*1024 # 5 megabytes
  #     keepalive_requests 666 # default:100
  #     client_header_buffer_size 16 * 1024 # 16 kilobytes
  #   end
  #
  #   # the rest of the Unicorn configuration
  #   worker_processes 8
  #
  # See the documentation for the respective Revactor, ThreadSpawn,
  # and ThreadPool classes for descriptions and recommendations for
  # each of them.  The total number of clients we're able to serve is
  # +worker_processes+ * +worker_connections+, so in the above example
  # we can serve 8 * 400 = 3200 clients concurrently.
  #
  # The default is +keepalive_timeout+ is 5 seconds, which should be
  # enough under most conditions for browsers to render the page and
  # start retrieving extra elements for.  Increasing this beyond 5
  # seconds is not recommended.  Zero disables keepalive entirely
  # (but pipelining fully-formed requests is still works).
  #
  # The default +client_max_body_size+ is 1 megabyte (1024 * 1024 bytes),
  # setting this to +nil+ will disable body size checks and allow any
  # size to be specified.
  #
  # The default +keepalive_requests+ is 100, meaning a client may
  # complete 100 keepalive requests after the initial request before
  # \Rainbows! forces a disconnect.  Lowering this can improve
  # load-balancing characteristics as it forces HTTP/1.1 clients to
  # reconnect after the specified number of requests, hopefully to a
  # less busy host or worker process.  This may also be used to mitigate
  # denial-of-service attacks that use HTTP pipelining.
  def Rainbows!(&block)
    block_given? or raise ArgumentError, "Rainbows! requires a block"
    @block = true
    instance_eval(&block)
    ensure
      @block = false
  end

  def check! # :nodoc:
    @block or abort "must be inside a Rainbows! block"
  end

  def worker_connections(nr)
    check!
    set_int(:worker_connections, nr, 1)
  end

  def use(model, *options)
    check!
    mod = begin
      Rainbows.const_get(model)
    rescue NameError => e
      warn "error loading #{model.inspect}: #{e}"
      e.backtrace.each { |l| warn l }
      abort "concurrency model #{model.inspect} not supported"
    end
    Module === mod or abort "concurrency model #{model.inspect} not supported"
    options.each do |opt|
      case opt
      when Hash
        Rainbows::O.merge!(opt)
      when Symbol
        Rainbows::O[opt] = true
      else
        abort "cannot handle option: #{opt.inspect} in #{options.inspect}"
      end
    end
    mod.setup if mod.respond_to?(:setup)
    set[:use] = mod
  end

  def keepalive_timeout(seconds)
    check!
    set_int(:keepalive_timeout, seconds, 0)
  end

  def keepalive_requests(count)
    check!
    case count
    when nil, Integer
      set[:keepalive_requests] = count
    else
      abort "not an integer or nil: keepalive_requests=#{count.inspect}"
    end
  end

  def client_max_body_size(bytes)
    check!
    err = "client_max_body_size must be nil or a non-negative Integer"
    case bytes
    when nil
    when Integer
      bytes >= 0 or abort err
    else
      abort err
    end
    set[:client_max_body_size] = bytes
  end

  def client_header_buffer_size(bytes)
    check!
    set_int(:client_header_buffer_size, bytes, 1)
  end
end

# :enddoc:
# inject the Rainbows! method into Unicorn::Configurator
Unicorn::Configurator.__send__(:include, Rainbows::Configurator)
