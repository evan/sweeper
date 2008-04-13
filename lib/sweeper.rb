
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
          write(filename, lookup(filename, current, options['force']))
        rescue Problem => e          
          tries += 1 and retry if tries < 2
          puts "Skipped #{filename}: #{e.message}"
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
  
  def lookup(filename, tags = {}, force = false)
    updated = {}
    if force or (BASIC_KEYS - tags.keys).any?
      updated.merge!(lookup_basic(filename))
    end
    if options['genre'] and (force or (GENRE_KEYS - tags.keys).any?)
      updated.merge!(lookup_genre(updated.merge(tags)))
    end

    if force
      tags.merge(updated)
    else
      updated.merge(tags)
    end
  end
  
  def lookup_basic(filename)
    Dir.chdir File.dirname(binary) do
      response = silence { `./#{File.basename(binary)} #{filename}` }
      object = begin
        XSD::Mapping.xml2obj(response)
      rescue REXML::ParseException
        raise Problem, "Invalid response."
      end              
      raise Problem, "Not found." unless object
      
      tags = {}
      song = Array(object.track).first      
      
      BASIC_KEYS.each do |key|
        tags[key] = song.send(key) if song.respond_to? key
      end
      tags
    end
  end
  
  def lookup_genre(tags)
    return tags if tags['artist'].blank?
    response = open("http://ws.audioscrobbler.com/1.0/artist/#{URI.encode(tags['artist'])}/toptags.xml").read
    object = XSD::Mapping.xml2obj(response)
    return {} if !object.respond_to? :tag

    genres = Array(object.tag)[0..4].map(&:name)
    return {} if !genres.any?
    
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
    puts filename
    
    file = ID3Lib::Tag.new(filename, ID3Lib::V2)
    tags.each do |key, value|
      file.send("#{key}=", value)
      puts "  #{value}"
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