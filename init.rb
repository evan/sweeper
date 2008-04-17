# Windows RubyScript2Exe start point

require 'rubygems'
require 'rubyscript2exe'

files = (Dir["vendor/lastfm.fpclient.beta2.win32/*"] + Dir["*"]).reject do |s| 
  File.directory? s
end
RUBYSCRIPT2EXE.bin = files

require 'lib/sweeper'
load 'bin/sweeper'
