# -*- encoding: binary -*-

# base class for \Rainbows! concurrency models, this is currently used by
# ThreadSpawn and ThreadPool models.  Base is also its own
# (non-)concurrency model which is basically Unicorn-with-keepalive, and
# not intended for production use, as keepalive with a pure prefork
# concurrency model is extremely expensive.
module Rainbows::Base
  # :stopdoc:

  # this method is called by all current concurrency models
  def init_worker_process(worker) # :nodoc:
    super(worker)
    Rainbows::Response.setup
    Rainbows::MaxBody.setup
    Rainbows.worker = worker

    # we're don't use the self-pipe mechanism in the Rainbows! worker
    # since we don't defer reopening logs
    Rainbows::HttpServer::SELF_PIPE.each { |x| x.close }.clear

    # spawn Threads since Logger takes a mutex by default and
    # we can't safely lock a mutex in a signal handler
    trap(:USR1) { Thread.new { reopen_worker_logs(worker.nr) } }
    trap(:QUIT) { Thread.new { Rainbows.quit! } }
    [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown
    Rainbows::ProcessClient.const_set(:APP, Rainbows.server.app)
    logger.info "Rainbows! #@use worker_connections=#@worker_connections"
  end

  def process_client(client)
    client.process_loop
  end

  def self.included(klass) # :nodoc:
    klass.const_set :LISTENERS, Rainbows::HttpServer::LISTENERS
  end

  def reopen_worker_logs(worker_nr)
    logger.info "worker=#{worker_nr} reopening logs..."
    Unicorn::Util.reopen_logs
    logger.info "worker=#{worker_nr} done reopening logs"
    rescue
      Rainbows.quit! # let the master reopen and refork us
  end
  # :startdoc:
end
