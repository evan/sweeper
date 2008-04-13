
require "#{File.dirname(__FILE__)}/../lib/sweeper"

unless RUBY_PLATFORM =~ /win32/
  system("chmod a+x #{Sweeper.new.binary}")
end
