
require 'test/unit'
require "#{File.dirname(__FILE__)}/../../lib/sweeper"
require 'ruby-debug'

class SweeperTest < Test::Unit::TestCase
  def setup
    @orig_dir = "#{File.dirname(__FILE__)}/songs"
    system("rm -rf /tmp/songs; cp -r #{@orig_dir} /tmp")
    @dir = "/tmp/songs"
    @found_many = "#{@dir}/1_001.mp3"
    @found_one = "#{@dir}/1_010.mp3"
    @not_found = "#{@dir}/1_002.mp3"
    @invalid = "#{@dir}/1_003.mp3"
    @s = Sweeper.new(@dir)
  end
  
  def test_lookup
    assert_equal(
      {"artist"=>"Photon Band", 
        "title"=>"To Sing For You", 
        "url"=>"http://www.last.fm/music/Photon+Band/_/To+Sing+For+You"},
      @s.lookup(@found_many))
    assert_equal(
      {"artist"=>"Various Artists - Vagabond Productions",
        "title"=>"Sugar Man - Tom Heyman",
        "url"=> "http://www.last.fm/music/Various+Artists+-+Vagabond+Productions/_/Sugar+Man+-+Tom+Heyman"},
      @s.lookup(@found_one))
#    assert_equal({},
#     @s.lookup(@not_found))
    assert_raises(Sweeper::Problem) do
      @s.lookup(@invalid)
    end
  end
  
  def test_read
    assert_equal({}, 
      @s.read(@found_many))
    assert_equal({},
      @s.read(@not_found))    
  end
  
  def test_write
    @s.silence do
      @s.write(@found_many, @s.lookup(@found_many))
    end
    assert_equal(
      @s.lookup(@found_many),
      @s.read(@found_many))
  end
  
  def test_run
    out, file = $stdout.clone, Tempfile.new("test_run")
    $stdout.reopen(file)    
    @s.run    
    $stdout.reopen(out)
    
    assert_equal(
"/tmp/songs/1_001.mp3
  Photon Band
  To Sing For You
  http://www.last.fm/music/Photon+Band/_/To+Sing+For+You
/tmp/songs/1_002.mp3
  Various Artists
  Greater California / Jersey Thursday
  http://www.last.fm/music/Various+Artists/_/Greater+California+%2F+Jersey+Thursday
Skipped /tmp/songs/1_003.mp3:
  Lookup failure
",
      File.read(file.path)
    )
    
    file.unlink
  end
  
end