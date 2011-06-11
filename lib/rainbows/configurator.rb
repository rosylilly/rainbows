# -*- encoding: binary -*-

# This module adds \Rainbows! to the
# {Unicorn::Configurator}[http://unicorn.bogomips.org/Unicorn/Configurator.html]
# \Rainbows!-specific configuration options must be inside a the Rainbows!
# block, otherwise Unicorn::Configurator directives may be used anwwhere
# in the file.
#
#   Rainbows! do
#     use :ThreadSpawn # concurrency model to use
#     worker_connections 400
#     keepalive_timeout 0 # zero disables keepalives entirely
#     client_max_body_size 5*1024*1024 # 5 megabytes
#     keepalive_requests 666 # default:100
#     client_header_buffer_size 2 * 1024 # 2 kilobytes
#   end
#
#   # the rest of the Unicorn configuration...
#   worker_processes 8
#   stderr_path "/path/to/error.log"
#   stdout_path "/path/to/output.log"
module Rainbows::Configurator
  Unicorn::Configurator::DEFAULTS.merge!({
    :use => Rainbows::Base,
    :worker_connections => 50,
    :keepalive_timeout => 5,
    :keepalive_requests => 100,
    :client_max_body_size => 1024 * 1024,
    :client_header_buffer_size => 1024,
    :client_max_header_size => 112 * 1024,
    :copy_stream => IO.respond_to?(:copy_stream) ? IO : false,
  })

  # Configures \Rainbows! with a given concurrency model to +use+ and
  # a +worker_connections+ upper-bound.  This method should be called
  # inside a Unicorn/\Rainbows! configuration file.
  #
  # All other methods in Rainbows::Configurator must be called
  # inside this block.
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

  # This limits the number of connected clients per-process.  The total
  # number of clients on a server is +worker_processes+ * +worker_connections+.
  #
  # This option has no effect with the Base concurrency model, which is
  # limited to +1+.
  #
  # Default: 50
  def worker_connections(clients)
    check!
    set_int(:worker_connections, clients, 1)
  end

  # Select a concurrency model for use with \Rainbows!.  You must select
  # this with a Symbol (prefixed with ":").  Thus if you wish to select
  # the Rainbows::ThreadSpawn concurrency model, you would use:
  #
  #   Rainbows! do
  #     use :ThreadSpawn
  #   end
  #
  # See the {Summary}[link:Summary.html] document for a summary of
  # supported concurrency models.  +options+ may be specified for some
  # concurrency models, but the majority do not support them.
  #
  # Default: :Base (no concurrency)
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

  # Sets the value (in seconds) the server will wait for a client in
  # between requests.  The default value should be enough under most
  # conditions for browsers to render the page and start retrieving
  # extra elements.
  #
  # Setting this value to +0+ disables keepalive entirely
  #
  # Default: 5 seconds
  def keepalive_timeout(seconds)
    check!
    set_int(:keepalive_timeout, seconds, 0)
  end

  # This limits the number of requests which can be made over a keep-alive
  # connection.  This is used to prevent single client from monopolizing
  # the server and to improve fairness when load-balancing across multiple
  # machines by forcing a client to reconnect.  This may be helpful
  # in mitigating some denial-of-service attacks.
  #
  # Default: 100 requests
  def keepalive_requests(count)
    check!
    case count
    when nil, Integer
      set[:keepalive_requests] = count
    else
      abort "not an integer or nil: keepalive_requests=#{count.inspect}"
    end
  end

  # Limits the maximum size of a request body for all requests.
  # Setting this to +nil+ disables the maximum size check.
  #
  # Default: 1 megabyte (1048576 bytes)
  #
  # If you want endpoint-specific upload limits and use a
  # "rack.input"-streaming concurrency model, see the Rainbows::MaxBody
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

  # Limits the maximum size of a request header for all requests.
  #
  # Default: 112 kilobytes (114688 bytes)
  #
  # Lowering this will lower worst-case memory usage and mitigate some
  # denial-of-service attacks.  This should be larger than
  # client_header_buffer_size.
  def client_max_header_size(bytes)
    check!
    set_int(:client_max_header_size, bytes, 8)
  end

  # This governs the amount of memory allocated for an individual read(2) or
  # recv(2) system call when reading headers.  Applications that make minimal
  # use of cookies should not increase this from the default.
  #
  # Rails applications using session cookies may want to increase this to
  # 2048 bytes or more depending on expected request sizes.
  #
  # Increasing this will increase overall memory usage to your application,
  # as you will need at least this amount of memory for every connected client.
  #
  # Default: 1024 bytes
  def client_header_buffer_size(bytes)
    check!
    set_int(:client_header_buffer_size, bytes, 1)
  end

  # Allows overriding the +klass+ where the +copy_stream+ method is
  # used to do efficient copying of regular files, pipes, and sockets.
  #
  # This is only used with multi-threaded concurrency models:
  #
  # * ThreadSpawn
  # * ThreadPool
  # * WriterThreadSpawn
  # * WriterThreadPool
  # * XEpollThreadSpawn
  # * XEpollThreadPool
  #
  # Due to existing {bugs}[http://redmine.ruby-lang.org/search?q=copy_stream]
  # in the Ruby IO.copy_stream implementation, \Rainbows! uses the
  # "sendfile" RubyGem that instead of copy_stream to transfer regular files
  # to clients.  The "sendfile" RubyGem also supports more operating systems,
  # and works with more concurrency models.
  #
  # Recent Linux 2.6 users may override this with "IO::Splice" from the
  # "io_splice" RubyGem:
  #
  #   require "io/splice"
  #   Rainbows! do
  #     copy_stream IO::Splice
  #   end
  #
  # Keep in mind that splice(2) itself is a relatively new system call
  # and has been buggy in many older Linux kernels.  If you're proxying
  # the output of sockets to the client, be sure to use "io_splice"
  # 4.1.1 or later to avoid stalling responses.
  #
  # Default: IO on Ruby 1.9+, false otherwise
  def copy_stream(klass)
    check!
    if klass && ! klass.respond_to?(:copy_stream)
      abort "#{klass} must respond to `copy_stream' or be `false'"
    end
    set[:copy_stream] = klass
  end
end

# :enddoc:
# inject the Rainbows! method into Unicorn::Configurator
Unicorn::Configurator.__send__(:include, Rainbows::Configurator)
