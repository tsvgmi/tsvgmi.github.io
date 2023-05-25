# Handling of playorder
class PlayOrder
  attr_reader :playlist, :content_str

  def self.hac_song_info(url)
    sf = url.split('/')
    sid = sf[4]
    sname = sf[5]
    version = sf[6]
    cfile = "data/SONGS/song:#{sid}:#{version}:#{sname}"

    if test('s', cfile)
      sinfo = YAML.load_file(cfile)
    else
      sinfo = HacSource.new.lyric_info(url)
      File.open(cfile, 'w') do |fod|
        fod.puts sinfo.to_yaml
      end
      sinfo
    end
    sinfo
  end

  def initialize(list_info, options={})
    @list_id    = list_info.is_a?(Hash) ? list_info[:id] : list_info
    @order_file = "data/#{@list_id}.order"
    @playlist   = PlayList.new(list_info)
    if test('f', @order_file)
      @content_str = _content_str
      if options[:range]
        rstart, rend = options[:range].split(',')
        @content_str = @content_str[rstart.to_i..rend.to_i]
      end
    else
      create_file
    end
  end

  def singers(active: true)
    content_str = @content_str
    content_str = content_str.select { |_sid, sinfo| sinfo[:active] } if active
    content_str.map do |_sid, sinfo|
      sinfo[:singer]
    end.compact.uniq.sort
  end

  def leads(active: true)
    content_str = @content_str
    content_str = content_str.select { |_sid, sinfo| sinfo[:active] } if active
    content_str.map do |_sid, sinfo|
      sinfo[:lead]
    end.compact.uniq.sort
  end

  def self.all_references
    wset = {}
    Dir.glob('data/*.order').each do |afile|
      File.read(afile).split("\n").each do |aline|
        next if aline =~ /^\s*#/

        key, *values = aline.chomp.sub(/,+$/, '').split(',')
        # Plog.dump_info(afile:afile, key:key, values:values)
        next unless values.size >= 3

        wset[key.to_i] ||= []
        wset[key.to_i] << "#{key},#{values.join(',')}"
        # Plog.dump_info(afile:afile, key:key, values:values)
      end
    end
    wset
  end

  def create_file
    test('f', @order_file) && File.delete(@order_file)
    wset   = self.class.all_references
    # Plog.dump_info(wset:wset.keys)
    output = []
    @playlist.fetch[:content].sort_by { |r| r[:name] }.each do |r|
      Plog.dump_info(r:)
      fs = r[:href].split('/')
      if wset[r[:song_id]]
        Plog.dump_info(previous: wset[r[:song_id]])
        output.concat(wset[r[:song_id]])
      else
        output << "#{r[:song_id]},#{fs[5]},,,,,,,"
      end
    end
    write_file(output.join("\n"))
  end

  def fetch_song_list
    qorder = @content_str.map { |r| r[0] }
    res    = @playlist.fetch[:content].select do |asong|
      qorder.include?(asong[:song_id])
    end
    res.sort_by { |asong| qorder.index(asong[:song_id]) }
  end

  def fetch_songs
    order_list = Hash[@content_str]
    fetch_song_list.map do |asong|
      oinfo = order_list[asong[:song_id]]
      url   = asong[:href].sub(%r{/*$}, '')
      # Plog.dump_info(url:url)
      url += "/#{oinfo[:version]}" if oinfo[:version] && !oinfo[:version].empty?
      asong.update(self.class.hac_song_info(url))
    end
  end

  def content
    test('f', @order_file) ? File.read(@order_file) : ''
  end

  def _content_str
    return {} unless test('f', @order_file)

    lno        = 0
    order_list = []
    Plog.info(msg: "Loading #{@order_file}")
    read_file.each do |r|
      song_id, title, version, singer, skey, style, tempo, lead, solo_idx =
        r.chomp.split(',')
      next unless title

      song_id = song_id.to_i
      if song_id < 0
        song_id = -1 * song_id
        active  = false
      else
        active = true
      end
      rec = {
        song_id:,
        title:,
        version:    version && !version.empty? ? version : nil,
        singer:,
        singer_key: skey,
        style:,
        tempo:,
        lead:,
        order:      lno,
        solo_idx:,
        active:,
      }
      lno += 1
      order_list << [song_id, rec]
    end
    # Plog.dump_info(order_list:order_list)
    order_list
  end

  def refresh_file
    song_list = @playlist.fetch(new: true)[:content].group_by { |r| r[:song_id] }
    wset      = {}
    output    = []
    Plog.info('Refresh data')
    read_file.each do |l|
      sno = l.split(',')[0]
      if song_list[sno.to_i.abs]
        output << l
        song_list.delete(sno.to_i.abs)
      end
    end
    wset      = self.class.all_references
    output += song_list.map do |sid, recs|
      sname = recs[0][:href].split('/')[5]
      if wset[sid]
        Plog.dump_info(previous: wset[sid])
        wset[sid].first
      else
        version = if !Dir.glob("thienv/#{sid}:*").empty?
                    'thienv'
                  else
                    ''
                  end
        "#{sid},#{sname},#{version},,,,"
      end
    end
    write_file(output.join("\n"))
  end

  def read_file
    if test('f', @order_file)
      File.read(@order_file).split("\n").reject { |l| l =~ /^\s*#/ }
    else
      []
    end
  end

  def write_file(new_content)
    File.open(@order_file, 'w') do |fod|
      fod.puts '# song_id,title,version,singer,skey,style,tempo,lead,solo_idx'
      fod.puts new_content
    end
    @content_str = _content_str
  end
end


