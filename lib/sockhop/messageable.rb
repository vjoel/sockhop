# Overrides some methods to give message-oriented behavior to a stream-
# oriented protocol. Works with any class that has #send and #recv API
# like Socket subclasses.
module Messageable
  class Error < StandardError; end
  class MessageLengthError < Error; end

  MAXLEN  = 100_000_000
  LEN_LEN = [0].pack("N").size

  # Send a message over the socket. The message is like a datagram rather
  # than a stream of data.
  def send_message(message)
    len = message.length
    if len > MAXLEN
      raise MessageLengthError, "MAXLEN exceeded: #{len} > #{MAXLEN}"
    end
    send([len].pack("N"), 0)
    send(message, 0)
  end

  # Receive a message from the socket. Returns +nil+ when there are no
  # more messages (the writer has closed its end of the socket).
  def recv_message(max_len = MAXLEN)
    lendata = recv_complete(LEN_LEN) or return nil
    len = lendata.unpack("N").first
    if len > max_len
      raise MessageLengthError, "max_len exceeded: #{len} > #{max_len}"
    end
    len == 0 ? "" : recv_complete(len)
  end
  
  # Tries to recv all +len+ bytes. Returns the data on success, _false_
  # if socket closed before specified number of bytes received.
  def recv_complete len
    buf = recv(len)
    while buf.length < len
      more = recv(len - buf.length)
      return false if not more or more.empty?
      buf << more
    end
    return buf
  end
end
