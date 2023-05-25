
# Extract Song Info
class SongInfo
  attr_reader :content

  def initialize(song_id, version=nil)
    fptn = if version
             "data/SONGS/song:#{song_id}:#{version}:*"
           else
             "data/SONGS/song:#{song_id}:{,*}:*"
           end
    @content = {}
    return if (sfile = Dir.glob(fptn)[0]).empty?

    if !test('s', sfile)
      Plog.dump_error(msg: 'File not found', sfile:)
    else
      @content = YAML.load_file(sfile)
    end
  end
end

