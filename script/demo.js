goog.provide('myapp.demo')

goog.require('goog.net.BrowserChannel')

var channel;
// channel.sendMap({message:'test'});

myapp.demo = function(message) {

  var handler = new goog.net.BrowserChannel.Handler();
  handler.channelOpened = function(channel) {
    channel.sendMap({message:message});
  };
  handler.channelHandleArray = function(x, data) {
    alert(data[0]['message']);
  };

  channel = new goog.net.BrowserChannel();
  channel.setHandler(handler);
  channel.connect('demo.test', 'demo.channel');
  
}
goog.exportSymbol('myapp.demo', myapp.demo)
