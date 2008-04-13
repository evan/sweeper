
require 'rubygems'
require 'id3lib'
require 'xsd/mapping'
require 'activesupport'

class ID3Lib::Tag
  alias :url :comment
  alias :url= :comment=
end

class Sweeper

  class Problem < RuntimeError; end

  KEYS = ['artist', 'title', 'url']

  attr_reader :options

  def initialize(options = {})
    @dir = File.expand_path(options['dir'] || Dir.pwd)
    @options = options
  end
  
  def run
    @processed = 0
    recurse(@dir)
    if @processed == 0
      puts "No files found."
      exec "#{$0} --help"
    end
  end
  
  #private
  
  def recurse(dir)
    Dir["#{dir}/*"].each do |filename|
      if File.directory? filename and options['recursive']
        recurse(filename)
      elsif File.extname(filename) == ".mp3"
        @processed += 1
        tries = 0
        begin
          current = read(filename)
          remote = lookup(filename)
  
          if options['force']
            write(filename, remote)
          else
            write(filename, remote.except(*current.keys))
          end
        rescue Problem => e          
          tries += 1 and retry if tries < 2
          puts "Skipped #{filename}: #{e.message}"
        end
      end
    end
  end
  
  def read(filename)
    tags = {}
    song = ID3Lib::Tag.new(filename)
    
    KEYS.each do |key|      
      tags[key] = song.send(key) if !song.send(key).blank?
    end
    tags
  end
  
  def lookup(filename)
    Dir.chdir File.dirname(binary) do
      response = silence { `./#{File.basename(binary)} #{filename}` }
      object = XSD::Mapping.xml2obj(response)
      raise Problem, "Lookup failure" unless object
      
      tags = {}
      song = object.track.first      
      
      KEYS.each do |key|
        tags[key] = song.send(key) if song.respond_to? key
      end
      tags
    end
  end
  
  def write(filename, tags)
    return if tags.empty?
    puts filename
    
    file = ID3Lib::Tag.new(filename)
    tags.each do |key, value|
      file.send("#{key}=", value)
      puts "  #{value}"
    end
    file.update! unless options['dry']
  end    
  
  def binary
    @binary ||= "#{File.dirname(__FILE__)}/../vendor/" + 
      case RUBY_PLATFORM
        when /darwin/
          "lastfm.fpclient.beta2.OSX-intel/lastfmfpclient"
        when /win32/
          "lastfm.fpclient.beta2.win32/lastfmfpclient.exe"
        else 
          "lastfm.fpclient.beta2.linux-32/lastfmfpclient"
        end
  end
  
  def silence(outf = nil, errf = nil)
    # This method is annoying.
    outf, errf = Tempfile.new("stdout"), Tempfile.new("stderr")
    out, err = $stdout.clone, $stderr.clone
    $stdout.reopen(outf)
    $stderr.reopen(errf)
    begin
      yield
    ensure
      $stdout.reopen(out)
      $stderr.reopen(err)
      outf.close; outf.unlink
      errf.close; errf.unlink
    end
  end    
  
end