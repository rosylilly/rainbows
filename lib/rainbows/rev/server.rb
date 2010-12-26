# -*- encoding: binary -*-
# :enddoc:
class Rainbows::Rev::Server < Rev::IO
  CONN = Rainbows::Rev::CONN
  # CL and MAX will be defined in the corresponding worker loop

  def on_readable
    return if CONN.size >= MAX
    io = @_io.kgio_tryaccept and CL.new(io).attach(LOOP)
  end
end
