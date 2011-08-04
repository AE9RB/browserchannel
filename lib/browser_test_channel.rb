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

class BrowserTestChannel

  class Server
    def initialize options={}
      @options = {
        # alternate host prefix for clients with connection pool limits
        :host_prefix => nil,
        # network admins can block this host to disable streaming
        # '/mail/images/cleardot.gif' must be found on this host
        :blocked_prefix => nil,
      }.merge! options
    end
    def call env
      request = Rack::Request.new env
      if request.GET['MODE'] == 'init'
        [
          200,
          {'Content-Type' => 'application/javascript'}, 
          [[@options[:host_prefix], @options[:blocked_prefix]].to_json]
        ]
      else
        BrowserTestChannel.new request
        Thin::Connection::AsyncResponse
      end
    end
  end

  include EventMachine::Deferrable

  def initialize request
    @html_data_type = request.GET['TYPE'] == 'html'
    
    headers = {'Cache-Control' => 'no-cache'}
    headers['Content-Type'] = @html_data_type ? 'text/html' : 'application/javascript'
    request.env['async.callback'].call( [200, headers, self] )
    if @html_data_type
      @body_callback.call "<html><body>\n"
      if domain = request.GET['DOMAIN']
        @body_callback.call "<script>try{document.domain=#{domain.dump};}catch(e){}</script>\n"
      end
    end
    call '11111'
    EventMachine.add_timer(2) do
      call '2'
      if @html_data_type
        @body_callback.call "<script>try{parent.d();}catch(e){}</script>\n</body></html>\n"
      end
      succeed
    end
  end

  def each &blk
    @body_callback = blk
  end

  def call chunk
    if @html_data_type
      @body_callback.call "<script>try{parent.m(#{chunk.dump});}catch(e){}</script>\n"
    else
      @body_callback.call chunk
    end
  end

end
