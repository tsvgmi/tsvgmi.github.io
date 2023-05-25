# Handling of play note
class PlayNote
  attr_reader :info

  def initialize(user)
    @plist_file = "data/#{user}-plist.json"
    @info       = if test('f', @plist_file)
                    JSON.parse(File.read(@plist_file), symbolize_names: true)
                  else
                    {}
                  end
  end

  def [](song_name)
    @info[song_name.to_sym]
  end

  def replace(_song_id, song_name, entry)
    require 'tempfile'
    require 'fileutils'

    @info[song_name.to_sym] = entry

    # Safer write
    tmpf = Tempfile.new('plist')
    tmpf.puts JSON.pretty_generate(@info)
    tmpf.close
    # Plog.dump_info(ofile:@plist_file, info:@info)
    FileUtils.move(tmpf.path, @plist_file, verbose: true, force: true)
  end
end


