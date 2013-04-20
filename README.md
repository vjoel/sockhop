# Sockhop #

A publish / subscribe server using sockets.

Sockhop works on Linux and Windows, at least.

Install the server:

    ruby install.rb config
    ruby install.rb setup
    ruby install.rb install

Basic help:

    sockhop -h

Run the server with defaults:

    sockhop

Run the server with a useful basic configuration (for linux):

    sockhop sample/sockhop.opts

Run the server with a useful basic configuration (for windows):

    sockhop sample/sockhop-win.opts

Run the sample clients (in separate terminals):

    ruby clients/pub.rb "my topic" "msg #%d" 100
    ruby clients/sub.rb "my topic"
    ruby clients/read.rb "my topic"

One client is a general mtcp shell that lets you send and receive messages (to one particular address):

    ruby clients/mtcp.rb <pub-server-addr>
    irb(#<MTCPClient:0xb7d0a11c>):001:0> send "some topic"      # publish to topic
    => 4
    irb(#<MTCPClient:0xb7d0a11c>):002:0> send "a test message"  # publish message
    => 14

Run the benchmark (not on windows, it uses fork()):

    ruby bemch/bench.rb

Run the unit tests:

    ruby test/test.rb

For the C API, see the subdir, c-api.
