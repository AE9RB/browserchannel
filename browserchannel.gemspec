# -*- encoding: utf-8 -*-
 
Gem::Specification.new do |s|
  s.name        = 'browserchannel'
  s.version     = '0.0.2.dev'
  s.authors     = ['David Turnbull']
  s.email       = ['dturnbull@gmail.com']
  s.homepage    = 'https://github.com/dturnbull/browserchannel'
  s.summary     = "An event-driven server for Google Closure Library's goog.BrowserChannel class"
  # s.description = ''
 
  s.add_dependency 'thin'

  s.files        = Dir.glob('lib/**/*') + %w(LICENSE README.md)
  s.require_path = 'lib'
end
