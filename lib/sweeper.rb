
require 'rubygems'
require 'id3lib'
require 'xsd/mapping'
require 'activesupport'
require 'open-uri'
require 'uri'
require 'Text'

require 'ruby-debug' if ENV['DEBUG']

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
  ALBUM_KEYS = ['album', 'track']
  GENRES = ID3Lib::Info::Genres
  GENRE_COUNT = 10
  DEFAULT_GENRE = {'genre' => 'Other', 'comment' => 'other'}

  attr_reader :options

  # Instantiate a new Sweeper. See <tt>bin/sweeper</tt> for <tt>options</tt> details.
  def initialize(options = {})
    @dir = File.expand_path(options['dir'] || Dir.pwd)
    @options = options
    @errf = Tempfile.new("stderr")
    @match_cache = {}    
  end
  
  # Run the Sweeper according to the <tt>options</tt>.
  def run      
    @read = 0
    @updated = 0
    @failed = 0

    Kernel.at_exit do
      if @read == 0
        puts "No mp3 files found. Maybe you meant --recursive?"
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
  
  # Recurse one directory, reading, looking up, and writing each file, if appropriate. Accepts a directory path.
  def recurse(dir)
    # Hackishly avoid problems with metacharacters in the Dir[] string.
    dir = dir.gsub(/[^\s\w\.\/\\\-]/, '?')
    # p dir if ENV['DEBUG']
    Dir["#{dir}/*"].each do |filename|
      if File.directory? filename and options['recursive']
        recurse(filename)
      elsif File.extname(filename) =~ /\.mp3$/i
        @read += 1
        tries = 0
        begin
          current = read(filename)  
          updated = lookup(filename, current)
          
          if ENV['DEBUG']
            p current, updated
          end

          if updated != current 
            # Don't bother updating identical metadata.
            write(filename, updated)
            @updated += 1
          else
            puts "Unchanged: #{File.basename(filename)}"
          end
          
        rescue Problem => e          
          tries += 1 and retry if tries < 2
          puts "Skipped (#{e.message.gsub("\n", " ")}): #{File.basename(filename)}"
          @failed += 1
        end
      end
    end  
  end
  
  # Read tags from an mp3 file. Returns a tag hash.
  def read(filename)
    tags = {}
    song = load(filename)
    
    (BASIC_KEYS + GENRE_KEYS).each do |key|      
      tags[key] = song.send(key) if !song.send(key).blank?
    end
    
    # Change numeric genres into TCON strings
    # XXX Might not work well
    if tags['genre'] =~ /(\d+)/
      tags['genre'] = GENRES[$1.to_i]
    end
    
    tags
  end
  
  # Lookup all available remote metadata for an mp3 file. Accepts a pathname and an optional hash of existing tags. Returns a tag hash. 
  def lookup(filename, tags = {})
    tags = tags.dup
    updated = {}

    # Are there any empty basic tags we need to lookup?
    if options['force'] or 
      (BASIC_KEYS - tags.keys).any?
      updated.merge!(lookup_basic(filename))
    end

    # Are there any empty genre tags we need to lookup?
    if options['genre'] and 
      (options['force'] or options['genre'] == 'force' or (GENRE_KEYS - tags.keys).any?)
      updated.merge!(lookup_genre(updated.merge(tags)))
    end

    if options['force']
      # Force all remote tags.
      tags.merge!(updated)      
    elsif options['genre'] == 'force'
      # Force remote genre tags only.
      tags.merge!(updated.slice(*GENRE_KEYS))
    end

    # Merge back in existing tags.
    updated.merge(tags)    
  end
  
  # Lookup the basic metadata for an mp3 file. Accepts a pathname. Returns a tag hash.
  def lookup_basic(filename)
    Dir.chdir File.dirname(binary) do
      response = `./#{File.basename(binary)} #{filename.inspect} 2> #{@errf.path}`
      object = begin
        XSD::Mapping.xml2obj(response)
      rescue Object => e
        raise Problem, "#{e.class.name} - #{e.message}"
      end              
      raise Problem, "Fingerprint failed" unless object
      
      tags = {}
      song = Array(object.track).first      
      
      BASIC_KEYS.each do |key|
        tags[key] = song.send(key) if song.respond_to? key 
      end
      tags
    end
  end

  # Lookup the genre metadata for a set of basic metadata. Accepts a tag hash. Returns a genre tag hash.  
  def lookup_genre(tags)
    return DEFAULT_GENRE if tags['artist'].blank?
    
    response = begin 
      open("http://ws.audioscrobbler.com/1.0/artist/#{URI.encode(tags['artist'])}/toptags.xml").read
    rescue Object => e
      puts "Open-URI error: #{e.class.name} - #{e.message}" if ENV['DEBUG']
      return DEFAULT_GENRE
    end
    
    begin
      object = XSD::Mapping.xml2obj(response)
    rescue Object => e
      puts "XSD error: #{e.class.name} - #{e.message}" if ENV['DEBUG']
      return DEFAULT_GENRE
    end    
     
    return DEFAULT_GENRE if !object.respond_to? :tag

    genres = Array(object.tag)[0..(GENRE_COUNT - 1)].map(&:name)
    return DEFAULT_GENRE if !genres.any?
    
    primary = nil
    genres.each_with_index do |this, index|
      match, weight = nearest_genre(this)
      # Bias slightly towards higher tagging counts
      weight += ((GENRE_COUNT - index) / GENRE_COUNT / 4.0)

      if ['Rock', 'Pop', 'Rap'].include? match
        # Penalize useless genres
        weight = weight / 3.0
      end
            
      p [weight, match] if ENV['DEBUG']
      
      if !primary or primary.first < weight
        primary = [weight, match]
      end
    end
    
    {'genre' => primary.last, 'comment' => genres.join(", ")}
  end
  
  # Write tags to an mp3 file. Accepts a pathname and a tag hash.
  def write(filename, tags)
    return if tags.empty?
    puts "Updated: #{File.basename(filename)}"
    
    song = load(filename)
    
    tags.each do |key, value|
      song.send("#{key}=", value)
      puts "  #{key.capitalize}: #{value}"
    end
    ALBUM_KEYS.each do |key|
      puts "  #{key.capitalize}: #{song.send(key)}"
    end
    
    unless options['dry-run']
      song.update!(ID3Lib::V2) 
    end
  end    
  
  # Returns the path to the fingerprinter binary for this platform.
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
  
  # Loads metadata for an mp3 file. Looks for which ID3 version is already populated, instead of just the existence of frames.
  def load(filename) 
    ID3Lib::Tag.new(filename, ID3Lib::V_ALL)
  end  
  
  def nearest_genre(string)
    @match_cache[string] ||= begin
      results = {}
      GENRES.each do |genre|
        results[Text::Levenshtein.distance(genre, string)] = genre
      end    
      min = results.keys.min
      match = results[min]
      
      [match, normalize(match, string, min)]
    end    
  end
  
  def normalize(genre, string, weight)
    # XXX Algorithm may not be right
    if weight == 0
      1.0
    elsif weight >= genre.size
      0.0
    elsif genre.size >= string.size
      1.0 - (weight / genre.size.to_f)
    else
      1.0 - (weight / string.size.to_f)
    end    
  end  
  
end