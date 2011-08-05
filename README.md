#BrowserChannel Ruby Server
Copyright 2011 David Turnbull. Licensed under the Apache License, Version 2.0.

An event-driven server for Google Closure Library's goog.BrowserChannel class.

##Getting Started

### Step 1
Ensure you have a modern Ruby and RubyGems.
Version 1.8.6 and higher should work.  Run:

    gem install thin closure json
    thin start

### Step 2
Open your web browser and continue from there.
Check the thin log for the proper port.
It's most likely:

    http://localhost:3000/

##Getting to Production

The browser is started by attaching a handler to a channel.  The channel
then connects with a server.  The handler is your implementation.

    var handler = new goog.net.BrowserChannel.Handler();
    handler.channelOpened = function(channel) {
      // fire off a message immediately after connect
      channel.sendMap({message:'data'});
    };
    handler.channelHandleArray = function(x, data) {
      // messages from the server arrive here
      alert(data[0].message);
    };

    channel = new goog.net.BrowserChannel();
    channel.setHandler(handler);
    channel.connect('demo.test', 'demo.channel');

The server is a Rack application for the `thin` server.  Other Rack servers do
not support event-driven multi chunk responses.  Thin also enables use of the
epoll/kqueue interface which allows for tens of thousands of open connections.
Expect 500-1000 requests per second on a single core of modern hardware.

    # rackup-style example for config.ru
    gem 'browserchannel'
    require 'browser_channel'
    require 'browser_test_channel'
    map '/demo.channel' do
      run BrowserChannel::Server.new, :handler => MyHandler
    end
    map '/demo.test' do
      run BrowserTestChannel::Server.new
    end

Just like the browser side, there's a handler for your implementation.

    class MyHandler < BrowserChanner::Handler
      # this is an echo server
      def call post_data
        requests = decode_post_data post_data
        requests.each { |r| @session << [r] }
      end
      # called when channel session is final
      def terminate
      end
    end

Be sure not to deploy the Closure Script build tool or debug tools like
Rack::Reloader. These will severely affect performance and security.
Check your middleware if you're not seeing the benchmarks you expect.
