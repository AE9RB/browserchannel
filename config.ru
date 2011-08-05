#!/usr/bin/env ruby
Dir.chdir File.dirname(__FILE__)
require 'closure'
%w{lib/browser_channel lib/browser_test_channel}.each do |file|
  require File.expand_path file
end

unless String.respond_to? :bytesize
  # This only patches in on Ruby 1.8.6
  class String
    alias :bytesize :size
  end
end

Closure.add_source 'script', '/'
Closure.add_source 'closure-library', '/closure-library'
# Closure.config.compiler_jar = 'compiler.jar'
# Closure.config.java = 'java'

stack = proc {
  use Closure::Middleware, 'script/index'
  use Rack::CommonLogger
  use Rack::Reloader, 1
  map '/demo.channel' do
    run BrowserChannel::Server.new
  end
  map '/demo.test' do
    run BrowserTestChannel::Server.new
  end
  map '/' do
    run Rack::File.new '.'
  end
}

# Were we executed/loaded or used as a config.ru?
if Rack::Builder === self
  stack.call
else
  EventMachine.run do
    Rack::Handler::Thin.run(Rack::Builder.new(&stack), :Port => 3000) do |server|
     server.maximum_connections = 20_000
     server.maximum_persistent_connections = 15_000
    end
  end
end
