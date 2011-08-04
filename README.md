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
