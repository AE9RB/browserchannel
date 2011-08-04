# Copyright 2011 David Turnbull
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'
require 'thin'

class BrowserChannel

  class Server
    def initialize options={}
      @options = {
        # subclass this echo Handler or create your own
        :handler => Handler,
        # ensure a chunk is sent within these first few seconds because
        # waiting an entire interval looks too much like a broken server
        :keep_alive_first => 10,
        # every so often, send a noop chunk so we don't look dead
        :keep_alive_interval => 30,
        # alternate host prefix for clients with connection pool limits
        :host_prefix => nil,
        # number of seconds a session must be unbound before freed
        :gc_max_age => 120,
        # session garbage collection is run every x connects
        :gc_frequency => 100,
      }.merge! options
    end
    def call env
      BrowserChannel.new @options, env
      Thin::Connection::AsyncResponse          
    end
  end
  
  # Example Handler that echos data.
  class Handler
    REQ_REGEXP = /^req(\d*)_(.*)$/
    def initialize session
      @session = session
    end
    def unbind
    end
    def call post_data
      requests = decode_post_data post_data
      requests.each { |r| @session << [r] }
    end
    private 
    def decode_post_data post_data
      count = [0,post_data['count'].to_i].max
      requests = Array.new(count){Hash.new}
      post_data.each do |key, value|
        next unless match = REQ_REGEXP.match(key)
        index = match[1].to_i
        next if index < 0 or index >= count
        requests[index][match[2]] = value
      end
      requests
    end
  end

  # A Session manages two arrays of responses.  One is maintained in case the
  # connection is dropped so that we don't lose messages.  This gets truncated
  # as we receive 'AID' information from the client indicating the data was
  # received.  The other array collects outgoing data for the currently bound
  # channel so it can be sent in a single chunk with other data in the next tick.

  class Session

    @@sessions ||= {}
    @@sessions_gc_counter ||= 0

    ID_CHARACTERS = (('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a).freeze
  
    def self.new options, id, array_id
      if (@@sessions_gc_counter += 1) > options[:gc_frequency]
        @@sessions.delete_if do |key, object|
          !object.channel and Time.now - object.timestamp > options[:gc_max_age]
        end
        @@sessions_gc_counter = 0
      end
      if id
        session = @@sessions[id]
        if session and array_id and !array_id.empty?
          array_id = array_id.to_i
          session.messages.delete_if do |message_array_id, *data|
            break if message_array_id > array_id
            true
          end
        end
        return session 
      end
      while !id or @@sessions.has_key? id
        id = (0..32).map{ID_CHARACTERS[rand(ID_CHARACTERS.size)]}.join 
      end
      allocate.instance_eval do
        @handler = options[:handler].new self
        initialize id
        @@sessions[id] = self
      end
    end
  
    attr_accessor :id, :last_array_id, :messages, :timestamp, :channel
  
    def initialize id
      @id = id
      @last_array_id = -1
      @messages = []
      unbind(@channel = nil) # trick into init
    end
    
    def bind channel
      @channel = channel
      @channel_queue = []
    end

    # A channel will request to unbind itself after the connection completes.
    # It's possible another connection has taken over so abort if it looks so.
    def unbind channel
      return if @channel != channel
      @timestamp = Time.now
      bind nil
    end
    
    def destroy
      @handler.unbind if @handler.respond_to? :unbind
      @@sessions.delete @id
    end
    
    # Data from the browser arrives here.
    def call post_data
      session_bound = @channel ? 1 : 0
      pending_bytes = @messages.empty? ? 0 : @session.to_json.bytesize
      response = [session_bound, @last_array_id, pending_bytes]
      @handler.call post_data
      response
    end
  
    # Adds a new message and schedules it to be sent.
    # Magic ['stop'] will tell the browser server is going down.
    def push array
      message = [@last_array_id += 1, array]
      @messages << message
      return unless @channel
      if @channel_queue.empty?
        EventMachine.next_tick do
          if @channel
            @channel.send_data @channel_queue
            @channel_queue = []
          end
        end
      end
      @channel_queue << message
    end
    alias :<< :push

  end

  include EventMachine::Deferrable

  LATEST_CHANNEL_VERSION = 8
  NOOP = ['noop'.freeze].freeze

  def initialize options, env
    @options = options
    request = Rack::Request.new env
    request_GET = request.GET
    @session = Session.new @options, request_GET['SID'], request_GET['AID']
    unless @session
      request.env['async.callback'].call [400, {}, self]
      succeed
      return
    end
    if @session.last_array_id == -1
      @session << ['c', @session.id, @options[:host_prefix], LATEST_CHANNEL_VERSION]
    end
    @chunked = request_GET['CI'] == '0'
    @html_data_type = request_GET['TYPE'] == 'html'
    headers = {'Cache-Control' => 'no-cache'}
    headers['Content-Type'] = @html_data_type ? 'text/html' : 'application/javascript'
    request.env['async.callback'].call( [200, headers, self] )
    if @html_data_type
      @body_callback.call "<html><body>\n"
      if domain = request_GET['DOMAIN']
        @body_callback.call "<script>try{document.domain=#{domain.dump};}catch(e){}</script>\n"
      end
    end
    if request_GET['TYPE'] == 'terminate'
      @session.destroy
      succeed
      return
    end
    if request.post?
      request_POST = request.POST
      count = request_POST['count'].to_i
      return send_data @session.call request_POST if count > 0
    elsif request.get?
      @session.bind self 
      @last_message = Time.now - ( @options[:keep_alive_interval] -
                      [@options[:keep_alive_interval],@options[:keep_alive_first]].min )
      keep_alive if @chunked
      # Thin calls errback when connection closes, even after success
      errback do
        @timer.cancel if @chunked
        @session.unbind self
      end
    end
    send_data @session.messages unless @session.messages.empty?
  end
  
  def keep_alive
    idle = Time.now - @last_message
    if idle > @options[:keep_alive_interval]
      @session << NOOP
      idle = 0
    end
    @timer = EventMachine::Timer.new @options[:keep_alive_interval] - idle, &method(:keep_alive)
  end

  def each &block
    @body_callback = block
  end

  def send_data messages
    json = messages.to_json
    if @html_data_type
      @body_callback.call "<script>try{parent.m(#{json.dump});}catch(e){}</script>\n"
    else
      @body_callback.call "#{json.bytesize+1}\n#{json}\n"
    end
    @last_message = Time.now
    unless @chunked
      if @html_data_type
        @body_callback.call "<script>try{parent.d();}catch(e){}</script>\n</body></html>\n"
      end
      succeed 
    end
  end

end
