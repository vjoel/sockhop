# Subscriber example for sockhop. Needs sockhop installed or 
# set "RUBYLIB=/path/to/sockhop/lib" in your env. Run like:
#
#   ruby sub.rb [topic]

require 'socket'
require 'sockhop/messageable'

if true
  tmpdir = File.join(ENV["TMPDIR"], "sockhop")
  sub_server_path = File.join(tmpdir, "sub-server.sock")
  s = UNIXSocket.open(File.expand_path(sub_server_path))
else
  s = TCPSocket.open("127.0.0.1", 30123)
end

s.extend Messageable

topic = ARGV[0] || "foo"

s.send_message(topic)

while msg = s.recv_message
  puts msg
end
