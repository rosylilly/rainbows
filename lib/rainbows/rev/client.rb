# -*- encoding: binary -*-
# :enddoc:
class Rainbows::Rev::Client < ::Rev::IO
  include Rainbows::EvCore
  G = Rainbows::G
  SF = Rainbows::StreamFile
  CONN = Rainbows::Rev::CONN
  KATO = Rainbows::Rev::KATO
  DeferredResponse = Rainbows::Rev::DeferredResponse
  DeferredChunkResponse = Rainbows::Rev::DeferredChunkResponse

  def initialize(io)
    CONN[self] = false
    super(io)
    post_init
    @deferred = nil
  end

  def want_more
    enable unless enabled?
  end

  def quit
    super
    close if @deferred.nil? && @_write_buffer.empty?
  end

  # override the ::Rev::IO#write method try to write directly to the
  # kernel socket buffers to avoid an extra userspace copy if
  # possible.
  def write(buf)
    if @_write_buffer.empty?
      begin
        case rv = @_io.kgio_trywrite(buf)
        when nil
          return enable_write_watcher
        when :wait_writable
          break # fall through to super(buf)
        when String
          buf = rv # retry, skb could grow or been drained
        end
      rescue => e
        return handle_error(e)
      end while true
    end
    super(buf)
  end

  def on_readable
    buf = @_io.kgio_tryread(16384)
    case buf
    when :wait_readable
    when nil # eof
      close
    else
      on_read buf
    end
  rescue Errno::ECONNRESET
    close
  end

  # queued, optional response bodies, it should only be unpollable "fast"
  # devices where read(2) is uninterruptable.  Unfortunately, NFS and ilk
  # are also part of this.  We'll also stick DeferredResponse bodies in
  # here to prevent connections from being closed on us.
  def defer_body(io)
    @deferred = io
    enable_write_watcher
  end

  # allows enabling of write watcher even when read watcher is disabled
  def evloop
    LOOP # this constant is set in when a worker starts
  end

  def next!
    @deferred = nil
    enable_write_watcher
  end

  def timeout?
    @deferred.nil? && @_write_buffer.empty? and close.nil?
  end

  # used for streaming sockets and pipes
  def stream_response(status, headers, io, body)
    c = stream_response_headers(status, headers) if headers
    # we only want to attach to the Rev::Loop belonging to the
    # main thread in Ruby 1.9
    io = (c ? DeferredChunkResponse : DeferredResponse).new(io, self, body)
    defer_body(io.attach(LOOP))
  end

  def rev_write_response(response, alive)
    status, headers, body = response
    headers = @hp.headers? ? HH.new(headers) : nil

    headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE if headers
    if body.respond_to?(:to_path)
      io = body_to_io(body)
      st = io.stat

      if st.file?
        offset, count = 0, st.size
        if headers
          if range = make_range!(@env, status, headers)
            status, offset, count = range
          end
          write(response_header(status, headers))
        end
        return defer_body(SF.new(offset, count, io, body))
      elsif st.socket? || st.pipe?
        return stream_response(status, headers, io, body)
      end
      # char or block device... WTF? fall through to body.each
    end
    write(response_header(status, headers)) if headers
    write_body_each(self, body, nil)
  end

  def app_call
    KATO.delete(self)
    @env[RACK_INPUT] = @input
    @env[REMOTE_ADDR] = @_io.kgio_addr
    response = APP.call(@env.update(RACK_DEFAULTS))

    rev_write_response(response, alive = @hp.next? && G.alive)
    return quit unless alive && :close != @state
    @state = :headers
    disable if enabled?
  end

  def on_write_complete
    case @deferred
    when DeferredResponse then return
    when NilClass # fall through
    else
      begin
        return rev_sendfile(@deferred)
      rescue EOFError # expected at file EOF
        close_deferred
      end
    end

    case @state
    when :close
      close if @_write_buffer.empty?
    when :headers
      if @buf.empty?
        unless enabled?
          enable
          KATO[self] = Time.now
        end
      else
        on_read("")
      end
    end
    rescue => e
      handle_error(e)
  end

  def handle_error(e)
    close_deferred
    if msg = Rainbows::Error.response(e)
      @_io.kgio_trywrite(msg) rescue nil
    end
    @_write_buffer.clear
    ensure
      quit
  end

  def close_deferred
    case @deferred
    when DeferredResponse, NilClass
    else
      begin
        @deferred.close
      rescue => e
        G.server.logger.error("closing #@deferred: #{e}")
      end
      @deferred = nil
    end
  end

  def on_close
    close_deferred
    CONN.delete(self)
    KATO.delete(self)
  end
end
