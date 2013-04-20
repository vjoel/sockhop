#!/usr/bin/env ruby

require 'test/unit'
require 'drb'
require 'fileutils'

# only require the _client_ libs
require 'socket'
require 'sockhop/messageable'

module SockhopTestUtils
  def run_pubsub opts
    require 'sockhop'
    @pubsub = PubSub.new opts
    trap "INT" do
      exit
    end
    @pubsub.run
  end
  
  # test clients can use this to communicate back to test process:
  class Backplane
    class TimeoutError < StandardError; end
    
    def initialize max_length = 10000 # long enough for test data
      @dst, @src = Socket.pair(Socket::PF_UNIX, Socket::SOCK_SEQPACKET, 0)
      @max_length = max_length
    end

    def put obj
      @src.send(Marshal.dump(obj), 0)
    end

    def get(timeout = nil)
      if timeout and not IO.select([@dst], nil, nil, timeout)
        raise TimeoutError
      end
      data = @dst.recv(@max_length)
      Marshal.load(data)
    end
  end
end

class Test_Sockhop < Test::Unit::TestCase
  include SockhopTestUtils
  
  def setup
    tmpdir = File.join(ENV["TMPDIR"], "sockhop-test")
    FileUtils.mkdir_p tmpdir
    
    @opts = {
      "logfile"           => nil, # to STDERR
      "daemonize"         => false,
      "sub_server_path"   => File.join(tmpdir, "sub-server.sock"),
      "pub_server_path"   => File.join(tmpdir, "pub-server.sock"),
      "read_server_path"  => File.join(tmpdir, "read-server.sock"),
      "sub_server_addr"   => "127.0.0.1:30123",
      "pub_server_addr"   => "127.0.0.1:30124",
      "read_server_addr"  => "127.0.0.1:30125",
      "control_addr"      => File.join(tmpdir, "control.sock"),
      "max_length"        => 100_000 # just to catch bad data
    }

    @pubsub_pid = fork {run_pubsub @opts}
    sleep 0.2

    # after forking the pubsub
    @backplane = Backplane.new
  end
  
  def teardown
    Process.kill "INT", @pubsub_pid ## or use control sock
    Process.waitall
  end
  
  def test_unix_pub_sub
    fork {unix_sub}
    
    result = nil
    assert_nothing_raised do
      result = @backplane.get(1.0) # expecting "ready"
    end
    
    unless result == "ready"
      flunk "unix_sub didn't start correctly: #{result.inspect}"
    end
    
    fork {unix_pub}
    
    assert_nothing_raised do
      result = @backplane.get(10.0) # long enought to finish
    end
    
    case result
    when Exception
      flunk result
    else
      puts result
    end
  end
  
  MSG = "test msg %d"

  def unix_pub topic = "test topic", n = 100
    s = UNIXSocket.open(File.expand_path(@opts["pub_server_path"]))
    s.extend Messageable
    s.send_message(topic)

    n.times do |i|
      sleep 0.001
      s.send_message(MSG % i)
    end
  end
  
  def unix_sub topic = "test topic", n = 100
    s = UNIXSocket.open(File.expand_path(@opts["sub_server_path"]))
    s.extend Messageable
    s.send_message(topic)
    
    a = []
    
    @backplane.put "ready"
    
    ## timeout...
    n.times do |i|
      msg = s.recv_message
      a << msg
      unless msg == MSG % i
        raise "wrong msg: #{msg.inspect}; " +
          "was expecting #{(MSG % i).inspect}; received #{a.inspect}"
      end
    end
    
    @backplane.put "messages received: #{n}"
  
  rescue => ex
    @backplane.put ex
  end
  
  ## test disconnect/reconnect
  
  ## test multiple topics
  
  ## test large msgs
  
  ## test buffer full
  
  ## test tcp
end
