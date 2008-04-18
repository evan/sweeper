# Windows RubyScript2Exe start point

require 'rubygems'
require 'rubyscript2exe'

RUBYSCRIPT2EXE.bin = Dir["vendor/lastfm.fpclient.beta2.win32/*"]

require 'net/http'
require 'lib/sweeper'
load 'bin/sweeper'
