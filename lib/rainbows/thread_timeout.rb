# -*- encoding: binary -*-
require 'thread'

# Soft timeout middleware for thread-based concurrency models in \Rainbows!
# This timeout only includes application dispatch, and will not take into
# account the (rare) response bodies that are dynamically generated while
# they are being written out to the client.
#
# In your rackup config file (config.ru), the following line will
# cause execution to timeout in 1.5 seconds.
#
#    use Rainbows::ThreadTimeout, :timeout => 1.5
#    run MyApplication.new
#
# You may also specify a threshold, so the timeout does not take
# effect until there are enough active clients.  It does not make
# sense to set a +:threshold+ higher or equal to the
# +worker_connections+ \Rainbows! configuration parameter.
# You may specify a negative threshold to be an absolute
# value relative to the +worker_connections+ parameter, thus
# if you specify a threshold of -1, and have 100 worker_connections,
# ThreadTimeout will only activate when there are 99 active requests.
#
#    use Rainbows::ThreadTimeout, :timeout => 1.5, :threshold => -1
#    run MyApplication.new
#
# This middleware only affects elements below it in the stack, so
# it can be configured to ignore certain endpoints or middlewares.
#
# Timed-out requests will cause this middleware to return with a
# "408 Request Timeout" response.
#
# == Caveats
#
# Badly-written C extensions may not be timed out.  Audit and fix
# (or remove) those extensions before relying on this module.
#
# Do NOT, under any circumstances nest and load this in
# the same middleware stack.  You may load this in parallel in the
# same process completely independent middleware stacks, but DO NOT
# load this twice so it nests.  Things will break!
#
# This will behave badly if system time is changed since Ruby
# does not expose a monotonic clock for users, so don't change
# the system time while this is running.  All servers should be
# running ntpd anyways.
class Rainbows::ThreadTimeout

  # :stopdoc:
  #
  # we subclass Exception to get rid of normal StandardError rescues
  # in app-level code.  timeout.rb does something similar
  ExecutionExpired = Class.new(Exception)

  # The MRI 1.8 won't be usable in January 2038, we'll raise this
  # when we eventually drop support for 1.8 (before 2038, hopefully)
  NEVER = Time.at(0x7fffffff)

  def initialize(app, opts)
    # @timeout must be Numeric since we add this to Time
    @timeout = opts[:timeout]
    Numeric === @timeout or
      raise TypeError, "timeout=#{@timeout.inspect} is not numeric"

    if @threshold = opts[:threshold]
      Integer === @threshold or
        raise TypeError, "threshold=#{@threshold.inspect} is not an integer"
      @threshold == 0 and raise ArgumentError, "threshold=0 does not make sense"
      @threshold < 0 and @threshold += Rainbows.server.worker_connections
    end
    @app = app

    # This is the main datastructure for communicating Threads eligible
    # for expiration to the watchdog thread.  If the eligible thread
    # completes its job before its expiration time, it will delete itself
    # @active.  If the watchdog thread notices the thread is timed out,
    # the watchdog thread will delete the thread from this hash as it
    # raises the exception.
    #
    # key: Thread to be timed out
    # value: Time of expiration
    @active = {}

    # Protects all access to @active.  It is important since it also limits
    # safe points for asynchronously raising exceptions.
    @lock = Mutex.new

    # There is one long-running watchdog thread that watches @active and
    # kills threads that have been running too long
    # see start_watchdog
    @watchdog = nil
  end

  # entry point for Rack middleware
  def call(env)
    # Once we have this lock, we ensure two things:
    # 1) there is only one watchdog thread started
    # 2) we can't be killed once we have this lock, it's unlikely
    #    to happen unless @timeout is really low and the machine
    #    is very slow.
    @lock.lock

    # we're dead if anything in the next two lines raises, but it's
    # highly unlikely that they will, and anything such as NoMemoryError
    # is hopeless and we might as well just die anyways.
    # initialize guarantees @timeout will be Numeric
    start_watchdog(env) unless @watchdog
    @active[Thread.current] = Time.now + @timeout

    begin
      # It is important to unlock inside this begin block
      # Mutex#unlock really can't fail here since we did a successful
      # Mutex#lock before
      @lock.unlock

      # Once the Mutex was unlocked, we're open to Thread#raise from
      # the watchdog process.  This is the main place we expect to receive
      # Thread#raise.  @app is of course the next layer of the Rack
      # application stack
      @app.call(env)
    ensure
      # I's still possible to receive a Thread#raise here from
      # the watchdog, but that's alright, the "rescue ExecutionExpired"
      # line will catch that.
      @lock.synchronize { @active.delete(Thread.current) }
      # Thread#raise no longer possible here
    end
    rescue ExecutionExpired
      # If we got here, it's because the watchdog thread raised an exception
      # here to kill us.  The watchdog uses @active.delete_if with a lock,
      # so we guaranteed it's
      [ 408, { 'Content-Type' => 'text/plain', 'Content-Length' => '0' }, [] ]
  end

  # The watchdog thread is the one that does the job of killing threads
  # that have expired.
  def start_watchdog(env)
    @watchdog = Thread.new(env["rack.logger"]) do |logger|
      begin
        if @threshold
          # Hash#size is atomic in MRI 1.8 and 1.9 and we
          # expect that from other implementations.
          #
          # Even without a memory barrier, sleep(@timeout) vs
          # sleep(@timeout - time-for-SMP-to-synchronize-a-word)
          # is too trivial to worry about here.
          sleep(@timeout) while @active.size < @threshold
        end

        next_expiry = NEVER

        # We always lock access to @active, so we can't kill threads
        # that are about to release themselves from the eye of the
        # watchdog thread.
        @lock.synchronize do
          now = Time.now
          @active.delete_if do |thread, expire_at|
            # We also use this loop to get the maximum possible time to
            # sleep for if we're not killing the thread.
            if expire_at > now
              next_expiry = expire_at if next_expiry > expire_at
              false
            else
              # Terminate execution and delete this from the @active
              thread.raise(ExecutionExpired)
              true
            end
          end
        end

        # We always try to sleep as long as possible to avoid consuming
        # resources from the app.  So that's the user-configured @timeout
        # value.
        if next_expiry == NEVER
          sleep(@timeout)
        else
          # sleep until the next known thread is about to expire.
          sec = next_expiry - Time.now
          sec > 0.0 ? sleep(sec) : Thread.pass # give other threads a chance
        end
      rescue => e
        # just in case
        logger.error e
      end while true # we run this forever
    end
  end
  # :startdoc:
end
