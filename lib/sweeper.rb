
require 'rubygems'
require 'id3lib'
require 'xsd/mapping'
require 'activesupport'
require 'open-uri'
require 'uri'
require 'amatch'

class ID3Lib::Tag
  def url
    f = frame(:WORS)
    f ? f[:url] : nil
  end
  
  def url=(s)
    remove_frame(:WORS)    
    self << {:id => :WORS, :url => s} if s.any?
  end
end

class Sweeper

  class Problem < RuntimeError; end

  BASIC_KEYS = ['artist', 'title', 'url']
  GENRE_KEYS = ['genre', 'comment']
  GENRES = ID3Lib::Info::Genres.sort
  GENRE_COUNT = 7
  DEFAULT_GENRE = {'genre' => 'Other', 'comment' => 'other'}

  attr_reader :options

  def initialize(options = {})
    options['genre'] ||= options['force-genre']
    @dir = File.expand_path(options['dir'] || Dir.pwd)
    @options = options
  end
  
  def run      
    @read = 0
    @updated = 0
    @failed = 0

    Kernel.at_exit do
      if @read == 0
        puts "No files found. Maybe you meant --recursive?"
        exec "#{$0} --help"
      else
        puts "Read: #{@read}\nUpdated: #{@updated}\nFailed: #{@failed}"
      end
    end      
  
    begin
      recurse(@dir)
    rescue Object => e
      puts "Unknown error: #{e.inspect}"
      ENV['DEBUG'] ? raise : exit
    end
  end
  
  #private
  
  def recurse(dir)
    Dir["#{dir}/*"].each do |filename|
      if File.directory? filename and options['recursive']
        recurse(filename)
      elsif File.extname(filename) == ".mp3"
        @read += 1
        tries = 0
        begin
          current = read(filename)  
          updated = lookup(filename, current)
          
          if updated != current
            write(filename, updated)
            @updated += 1
          end
          
        rescue Problem => e          
          tries += 1 and retry if tries < 2
          puts "Skipped #{filename}: #{e.message}"
          @failed += 1
        end
      end
    end
  end
  
  def read(filename)
    tags = {}

    song = ID3Lib::Tag.new(filename, ID3Lib::V2)
    if song.empty?
      song = ID3Lib::Tag.new(filename, ID3Lib::V1)
    end
    
    (BASIC_KEYS + GENRE_KEYS).each do |key|      
      tags[key] = song.send(key) if !song.send(key).blank?
    end
    
    tags
  end
  
  def lookup(filename, tags = {})
    updated = {}
    if options['force'] or 
      (BASIC_KEYS - tags.keys).any?
      updated.merge!(lookup_basic(filename))
    end
    if options['genre'] and 
      (options['force'] or options['force-genre'] or (GENRE_KEYS - tags.keys).any?)
      updated.merge!(lookup_genre(updated.merge(tags)))
    end

    if options['force']
      tags.merge!(updated)      
    elsif options['force-genre']
      tags.merge!(updated.slice('genre', 'comment'))
    end

    updated.merge(tags)    
  end
  
  def lookup_basic(filename)
    Dir.chdir File.dirname(binary) do
      response = silence { `./#{File.basename(binary)} #{filename.inspect}` }
      object = begin
        XSD::Mapping.xml2obj(response)
      rescue REXML::ParseException
        raise Problem, "Server sent invalid response."
      end              
      raise Problem, "Fingerprint failed or not found." unless object
      
      tags = {}
      song = Array(object.track).first      
      
      BASIC_KEYS.each do |key|
        tags[key] = song.send(key) if song.respond_to? key
      end
      tags
    end
  end
  
  def lookup_genre(tags)
    return DEFAULT_GENRE if tags['artist'].blank?
    
    response = begin 
      open("http://ws.audioscrobbler.com/1.0/artist/#{URI.encode(tags['artist'])}/toptags.xml").read
    rescue OpenURI::HTTPError
      return DEFAULT_GENRE
    end
    
    object = XSD::Mapping.xml2obj(response)
    return DEFAULT_GENRE if !object.respond_to? :tag

    genres = Array(object.tag)[0..(GENRE_COUNT - 1)].map(&:name)
    return DEFAULT_GENRE if !genres.any?
    
    primary = nil
    genres.each do |this|
      match_results = Amatch::Levenshtein.new(this).similar(GENRES)
      max = match_results.max
      match = GENRES[match_results.index(max)]

      if ['Rock', 'Pop', 'Rap'].include? match
        # Penalize useless genres
        max = max / 3.0
      end
      
      if !primary or primary.first < max
        primary = [max, match]
      end
    end
    
    {'genre' => primary.last, 'comment' => genres.join(" ")}
  end
  
  def write(filename, tags)
    return if tags.empty?
    puts File.basename(filename)
    
    file = ID3Lib::Tag.new(filename, ID3Lib::V2)
    tags.each do |key, value|
      file.send("#{key}=", value)
      puts "  #{key.capitalize}: #{value}"
    end
    file.update! unless options['dry-run']
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