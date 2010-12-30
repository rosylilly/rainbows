# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Response::Range
  HTTP_RANGE = 'HTTP_RANGE'
  Content_Range = 'Content-Range'.freeze
  Content_Length = 'Content-Length'.freeze

  # This does not support multipart responses (does anybody actually
  # use those?) +headers+ is always a Rack::Utils::HeaderHash
  def make_range!(env, status, headers)
    if 200 == status.to_i &&
        (clen = headers[Content_Length]) &&
        /\Abytes=(\d+-\d*|\d*-\d+)\z/ =~ env[HTTP_RANGE]
      a, b = $1.split(/-/)
      clen = clen.to_i
      if b.nil? # bytes=M-
        offset = a.to_i
        count = clen - offset
      elsif a.empty? # bytes=-N
        offset = clen - b.to_i
        count = clen - offset
      else  # bytes=M-N
        offset = a.to_i
        count = b.to_i + 1 - offset
      end
      raise Rainbows::Response416 if count <= 0 || offset >= clen
      count = clen if count > clen
      headers[Content_Length] = count.to_s
      headers[Content_Range] = "bytes #{offset}-#{offset+count-1}/#{clen}"
      [ 206, offset, count ]
    end
    # nil if no status
  end
end
