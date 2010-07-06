# -*- encoding: binary -*-
module Rainbows::ByteSlice
  if String.method_defined?(:encoding)
    def byte_slice(buf, range)
      if buf.encoding != Encoding::BINARY
        buf.dup.force_encoding(Encoding::BINARY).slice!(range)
      else
        buf[range]
      end
    end
  else
    def byte_slice(buf, range)
      buf[range]
    end
  end
end
