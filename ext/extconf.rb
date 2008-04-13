
require "#{File.dirname(__FILE__)}/../lib/sweeper"

unless RUBY_PLATFORM =~ /win32/
  system("chmod a+x #{Sweeper.new.binary}")
end

File.open("#{File.dirname(__FILE__)}/Makefile", 'w') do |f|
  f.puts "install: install"
end
