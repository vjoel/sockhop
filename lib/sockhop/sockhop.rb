require 'socket'
require 'fileutils'
require 'sockhop/messageable'
require 'logger'

class ObserverList
  attr_accessor :last_message
  attr_reader :observers
  
  def initialize
    @observers = []
  end
  
  # Called by a publisher when a new message is available. Calls the
  # notify method of subscribers, which must return true if the
  # subscriber is to be deleted.
  def notify msg
    @observers.delete_if do |obs|
      obs.notify msg
    end
  end
  
  # Called by a subscriber. The subscriber must implement a notify method.
  def add_observer(obs)
    @observers << obs
  end
end

class PubSub
  attr_reader :sub_server_path, :pub_server_path, :read_server_path
  attr_reader :sub_server_addr, :pub_server_addr, :read_server_addr
  attr_reader :control_addr
  attr_reader :max_length
  attr_accessor :recv_msg_count, :send_msg_count, :start_time, :start_times
  attr_reader :log, :topics, :socks
  
  def initialize opts
    logfile = opts["logfile"]
    case logfile
    when "STDERR", "stderr", nil
      logfile = STDERR
    else
      logfile = File.expand_path(logfile)
    end
    
    @log = Logger.new(logfile, 10, 10_000)
    @log.level = Logger::DEBUG ## ?

    @sub_server_path = opts["sub_server_path"]
    @pub_server_path = opts["pub_server_path"]
    
    @sub_server_addr = opts["sub_server_addr"]
    @pub_server_addr = opts["pub_server_addr"]
    
    @read_server_path = opts["read_server_path"]
    @read_server_addr = opts["read_server_addr"]
    
    @control_addr = opts["control_addr"]
    
    @max_length = opts["max_length"]
    @recv_msg_count = 0
    @send_msg_count = 0

    @topics = Hash.new {|h,k| h[k] = ObserverList.new}
    @socks = []
  end
  
  def run
    if control_addr
      s = nil
      begin # try IP addr
        addr, port = control_addr.split(":")
        raise unless port
        port = Integer(port)
      rescue # assume path to unix socket
        FileUtils.rm_f(control_addr)
        s = UNIXServer.open(File.expand_path(control_addr))
      else
        s = TCPServer.open(addr, port)
      end
      
p s
      s.extend ControlServer
      s.setup self, nil, 10_000
      socks << s
    end
    
    if sub_server_path
      FileUtils.rm_f(sub_server_path)
      s = UNIXServer.open(File.expand_path(sub_server_path))
      s.extend SubscriberServer
      s.setup self, topics, max_length
      socks << s
    end
    
    if sub_server_addr
      addr, port = sub_server_addr.split(":")
      port = Integer(port)
      s = TCPServer.open(addr, port)
      s.extend SubscriberServer
      s.setup self, topics, max_length
      socks << s
    end
    
    if pub_server_path
      FileUtils.rm_f(pub_server_path)
      s = UNIXServer.open(File.expand_path(pub_server_path))
      s.extend PublisherServer
      s.setup self, topics, max_length
      socks << s
    end
    
    if pub_server_addr
      addr, port = pub_server_addr.split(":")
      port = Integer(port)
      s = TCPServer.open(addr, port)
      s.extend PublisherServer
      s.setup self, topics, max_length
      socks << s
    end
    
    if read_server_path
      FileUtils.rm_f(read_server_path)
      s = UNIXServer.open(File.expand_path(read_server_path))
      s.extend ReadServer
      s.setup self, topics, max_length
      socks << s
    end
    
    if read_server_addr
      addr, port = read_server_addr.split(":")
      port = Integer(port)
      s = TCPServer.open(addr, port)
      s.extend ReadServer
      s.setup self, topics, max_length
      socks << s
    end

    loop do
      r = select(socks, nil, nil) ## check for errors, too?
      next unless r
      a = r.first
      a.each do |sock|
        sock.handle_input(socks)
      end
    end

  ensure
    cleanup
  end
  
  def cleanup
    subs = @topics.values.map {|ob_list| ob_list.observers}.flatten
    (@socks + subs).each {|s| s.close unless s.closed?}
    FileUtils.rm_f(sub_server_path) if sub_server_path
    FileUtils.rm_f(pub_server_path) if pub_server_path
    FileUtils.rm_f(read_server_path) if read_server_path
    FileUtils.rm_f(control_addr) if control_addr  ### and not TCP!
  end

  def report
    log.info "Stopping."
    lines = []
    lines << Process.times.inspect
    if start_times
      times = Process.times.to_a.inject{|s,x|s+x}
      cpu_sec = times - start_times
      elapsed = start_time ? Time.now - start_time : 0.0
      lines << "sent = #{send_msg_count}"
      lines << "recd = #{recv_msg_count}"
      lines << "msg per cpu sec = #{send_msg_count / cpu_sec}"
      lines << "msg per sec     = #{send_msg_count / elapsed}"
      lines << "%%cpu = %5.2f" % (100*cpu_sec/elapsed)
    end
    log << lines.join("\n")
    exit
  end
end

module GenericServer
  attr_accessor :pubsub, :max_length, :topics

  def setup pubsub, topics, max_length
    @pubsub = pubsub
    @topics = topics
    @max_length = max_length
  end

  def handle_input socks
    sock = accept
    sock.extend Messageable
    sock.extend sock_class
    sock.setup self
    socks << sock
  end
end

module ControlServer
  include GenericServer
  def sock_class; ControlSocket; end
  def inspect; "<ControlServer>"; end
end

module SubscriberServer
  include GenericServer
  def sock_class; SubscriberSocket; end
  def inspect; "<SubscriberServer>"; end
end

module PublisherServer
  include GenericServer
  def sock_class; PublisherSocket; end
  def inspect; "<PublisherServer>"; end
end

module ReadServer
  include GenericServer
  def sock_class; ReadSocket; end
  def inspect; "<ReadSocket>"; end
end

module GenericSocket
  attr_accessor :pubsub, :max_length, :topics

  def setup server
    @server = server
    @pubsub = server.pubsub
    @max_length = server.max_length
    @topics = server.topics
  end
end

module ControlSocket
  include GenericSocket

  def handle_input socks
    msg = recv_message(max_length)
    case msg
    when "restart"
      send_message "restarting"
      close
      socks.delete self
      pubsub.cleanup
      ### ?
    when "stop"
      send_message "stopping"
      close
      socks.delete self
      pubsub.cleanup
      exit
    end
  end
  
  def inspect; "<ControlSocket>"; end
end

module SubscriberSocket
  include GenericSocket
  
  def inspect
    "<SubscriberSocket: #{@tag}>"
  end
  
  def handle_input socks
    @tag = recv_message(@max_length)
    if @tag
      @ts = @topics[@tag]
      @ts.add_observer self
    end
    socks.delete self
  rescue Messageable::Error
    socks.delete self
    close
  end

  def notify msg
    if IO.select(nil, [self], nil, 0) ## inefficient?
        ## no way to tell if buffer has room for all of msg
      send_message(msg)
      @pubsub.send_msg_count += 1
    else
      peerstr = peeraddr.join(", ")
      @pubsub.log.error "buffer full in subscriber to #{@tag} [#{peerstr}]"
      ## drop message? error? delete subscriber?
    end
    false
  rescue => ex # typically, due to client going away
    @pubsub.log.error ex.inspect, ex.backtrace.join("\n  ") ## if debug mode?
    close unless closed?
    true # delete from observer list
  end
end

module PublisherSocket
  include GenericSocket
  
  def inspect
    "<PublisherSocket>"
  end
  
  def handle_input socks
    if @ts
      msg = recv_message(@max_length)
      if msg
        @ts.last_message = msg ## should this be optional?
        @ts.notify msg
        @pubsub.recv_msg_count += 1
        @pubsub.start_times ||= Process.times.to_a.inject{|s,x|s+x}
        @pubsub.start_time ||= Time.now
      else
        socks.delete self
        close
      end
      
    else
      @tag = recv_message(@max_length)
      if @tag
        @ts = @topics[@tag]
      else
        socks.delete self
        close
      end
    end

  rescue Messageable::Error
    socks.delete self
    close
  end
end

module ReadSocket
  include GenericSocket
  
  def inspect
    "<ReadSocket>"
  end
  
  def handle_input socks
    tag = recv_message(@max_length)
    if tag
      ts = @topics[tag]
      msg = ts.last_message
      notify(msg || "")
    else
      socks.delete self
      close
    end
  rescue Messageable::Error
    socks.delete self
    close
  end

  def notify msg
    if IO.select(nil, [self], nil, 0) ## inefficient? Better: nonblocking
      send_message(msg)
    else
      peerstr = peeraddr.join(", ")
      @pubsub.log.error "buffer full in reader of #{@tag} [#{peerstr}]"
      ## drop message? error? delete subscriber?
    end
  rescue => ex # typically, due to client going away
    @pubsub.log.error ex.inspect, ex.backtrace.join("\n  ") ## if debug mode?
    close unless closed?
  end
end
