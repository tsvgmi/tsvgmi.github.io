# SongStore definition
class SongStore
  attr_reader :file, :songs

  def initialize(file, _random: false)
    @file   = file
    @curptr = 0
    @songs  = []
    return unless test('s', file)

    @songs = YAML.load_file(file)
    @songs = songs.sort_by { rand } if rand
    Plog.info "Reading #{@songs.size} entries from #{@file}"
  end

  def save
    if @curptr < @songs.size
      csize = @songs.size - @curptr
      Plog.info "Writing remaining #{csize} entries to #{@file}"
      File.open(@file, 'w') do |fod|
        fod.puts @songs[@curptr..].to_yaml
      end
    else
      Plog.info "Complete list from #{@file}.  Removing it"
      File.delete(@file)
    end
  end

  # Overwrite everything here
  def write(slist)
    @songs  = slist
    @curptr = 0
    save
  end

  def advance(offset=1)
    @curptr += offset
  end

  def peek
    @songs[@curptr]
  end
end

