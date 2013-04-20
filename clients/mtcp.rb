#!/usr/bin/env ruby

# Sample client for arb. mtcp interfaces (not just sockhop)

#== Command line library

require 'irb'
require 'irb/completion'

module IRB
  def IRB.parse_opts
    # Don't touch ARGV, which belongs to the app which called this module.
  end
  
  def IRB.start_session(*args)
    unless $irb
      IRB.setup nil
      ## maybe set some opts here, as in parse_opts in irb/init.rb?
    end

    workspace = WorkSpace.new(*args)

    if @CONF[:SCRIPT] ## normally, set by parse_opts
      $irb = Irb.new(workspace, @CONF[:SCRIPT])
    else
      $irb = Irb.new(workspace)
    end

    @CONF[:IRB_RC].call($irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = $irb.context

    trap 'INT' do
      $irb.signal_handle
    end
    
    custom_configuration if defined?(IRB.custom_configuration)

    catch :IRB_EXIT do
      $irb.eval_input
    end
    
    ## might want to reset your app's interrupt handler here
  end
end

class Object
  include IRB::ExtendCommandBundle # so that Marshal.dump works
end

#== Socket interface

require 'socket'
require 'sockhop/messageable'

class MTCPClient
  attr_reader :host, :port, :path, :sock
  
  def initialize(*args)
    case args.size
    when 1
      @path = args[0]
    when 2
      @host, port = args
      @port = Integer(port)
    when 0
      raise ArgumentError, "too few arguments: #{args.inspect}"
    else
      raise ArgumentError, "too many arguments: #{args.inspect}"
    end
  end
  
  def connect
    if @path
      @sock = UNIXSocket.open(File.expand_path(@path))
    else
      @sock = TCPSocket.open(@host, @port)
    end
    @sock.extend Messageable    
  end
  
  def send msg
    @sock.send_message msg
  end
  
  def recv
    @sock.recv_message
  end
end

client = 
begin
  MTCPClient.new(*ARGV)
  
rescue => ex
  puts ex.message
  
  puts <<-END
  
    Usage:  #{$0} host port
            #{$0} /path/to/unix/socket
    
    Starts a command shell which supports the following commands (in
    addition to the ruby language):
    
      send message_string -- sends message_string to the destination
      
      recv                -- returns a message_string
    
    The message_string can be any text or binary data. Sending the mtcp
    formatted packet (length field followed by data) is handled for you.
    
    For example:
    
      send [1,2,3].pack("NNN")    # send numbers in network long format
      
      recv.unpack("NNN")          # receive numbers in network long format
    
  END
  exit!
end

client.connect
puts "Connected to #{client.inspect}"
IRB.start_session(client)
