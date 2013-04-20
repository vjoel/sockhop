# Publisher example for sockhop. Needs sockhop installed or 
# set "RUBYLIB=/path/to/sockhop/lib" in your env. Run like:
#
#   ruby pub.rb [topic [msg [count]]]
#
# msg string can contain %d output specifier to display counter in msg 

require 'socket'
require 'sockhop/messageable'

if true
  tmpdir = File.join(ENV["TMPDIR"], "sockhop")
  pub_server_path = File.join(tmpdir, "pub-server.sock")
  s = UNIXSocket.open(File.expand_path(pub_server_path))
else
  s = TCPSocket.open("127.0.0.1", 30124)
end

s.extend Messageable

topic = ARGV[0] || "foo"
msg = ARGV[1] || "test %d"
n = (ARGV[2] || 1000).to_i

s.send_message(topic)

s.send_message(msg % 1)
(2..n).each do |i|
  sleep 0.001
  s.send_message(msg % i)
end
