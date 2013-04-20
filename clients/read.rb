# Reader example for sockhop. Needs sockhop installed or 
# set "RUBYLIB=/path/to/sockhop/lib" in your env. Run like:
#
#   ruby read.rb [topic]

require 'socket'
require 'sockhop/messageable'

if true
  tmpdir = File.join(ENV["TMPDIR"], "sockhop")
  sub_server_path = File.join(tmpdir, "read-server.sock")
  s = UNIXSocket.open(File.expand_path(sub_server_path))
else
  s = TCPSocket.open("127.0.0.1", 30125)
end

s.extend Messageable

topic = ARGV[0] || "foo"

loop do
  s.send_message(topic)
  msg = s.recv_message
  puts msg
  sleep 1.0
end
