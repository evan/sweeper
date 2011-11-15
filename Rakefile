require 'echoe'

Echoe.new("sweeper") do |p|
  p.author = "Evan Weaver"
  p.project = "fauna"
  p.summary = "Automatically tag your music collection with metadata from Last.fm."
  p.url = "http://blog.evanweaver.com/files/doc/fauna/sweeper/"
  p.docs_host = "blog.evanweaver.com:~/www/bax/public/files/doc/"
  p.dependencies = ['id3lib-ruby', 'choice', 'Text', 'activesupport =2.1.0', 'soap4r', 'test-unit']
  p.clean_pattern = ['doc', 'pkg', 'test/integration/songs']
  p.rdoc_pattern = ['README', 'LICENSE', 'CHANGELOG', 'TODO', 'lib/*']
  p.need_zip = true
  p.need_tar_gz = false
end

task :binary do
  Dir.chdir(File.dirname(__FILE__)) do
    system("ruby c:/ruby/bin/rubyscript2exe init.rb")
    File.rename("init.exe", "sweeper.exe")
  end
end

