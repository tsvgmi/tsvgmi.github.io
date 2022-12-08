#!/usr/bin/env ruby
# frozen_string_literal: true

#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require "#{File.dirname(__FILE__)}/../etc/toolenv"
$LOAD_PATH << File.dirname(__FILE__)
require 'json'
require 'yaml'
require 'core'

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

# Playlist handling
class PlayList
  extend_cli __FILE__

  HAC_URL = 'https://hopamchuan.com'

  def initialize(list_info)
    if list_info.is_a?(Hash)
      listno = list_info[:id]
      @save_list = list_info.clone
    else
      listno = list_info
      @save_list = {id: listno}
    end
    @list_id = listno
  end

  def fetch(new: false)
    cfile = "data/list_content-#{@list_id}.yml"
    if !new && test('s', cfile)
      @save_list = YAML.load_file(cfile)
    else
      @save_list[:content] = HacSource.new.playlist("#{HAC_URL}/playlist/v/#{@list_id}")
      File.open(cfile, 'w') do |fod|
        fod.puts @save_list.to_yaml
      end
      @save_list
    end
    @save_list
  end

  class << self
    def band_singers
      %w[bich-hien gia-cau mai-huong michelle mike thanh
         thanh-liem thien thien-huong thuy-dung yen-phuong]
    end

    def collect_for_user(user, listno: nil, reload: false, options: {})
      reload = reload == 'true' if reload.is_a?(String)

      playlists = PlayList.for_user(user, reload:)
      raise "No playlists found for user #{user}" if playlists.size <= 0

      listno ||= playlists[0][:id]

      list_info  = playlists.find { |r| r[:id].to_i == listno.to_i }
      play_order = PlayOrder.new(listno, options)
      order_list = Hash[play_order.content_str]
      song_list  = play_order.fetch_songs
      {
        listno:,
        list_info:,
        playlists:,
        order_list:,
        song_list:,
        singers:    play_order.singers,
        leads:      play_order.leads,
        perf_info:  PlayNote.new(user),
      }
    end

    def for_user(user, reload: false)
      cfile = "data/list_for_user-#{user}.yml"
      if !reload && test('s', cfile)
        ulist = YAML.load_file(cfile)
      else
        ulist = HacSource.new.list_for_user("#{HAC_URL}/profile/playlists/#{user}")
        File.open(cfile, 'w') do |fod|
          fod.puts ulist.to_yaml
        end
        ulist
      end
    end

    def collect_for_singer(singer, reload: false)
      playlists  = PlayList.for_singer(singer, reload:)
      play_order = PlayOrder.new(singer)
      order_list = Hash[play_order.content_str]
      song_list  = play_order.fetch_songs
      {
        list_no:    singer,
        list_info:  playlists[0],
        playlists:,
        order_list:,
        song_list:,
        singers:    play_order.singers,
        leads:      play_order.leads,
        perf_info:  PlayNote.new('thienv'),
      }
    end

    def for_singer(singer, reload: false)
      gen_singer_list(singer, reload:)
      [
        {
          id:         singer,
          href:       "file:///#{Dir.pwd}/data/list_content-#{singer}.yml",
          name:       "List for #{singer}",
          song_count: 1,
        }
      ]
    end

    def gen_singer_list(singer, reload: false)
      order_file = "#{Dir.pwd}/data/#{singer}.order"
      Plog.dump_info(reload:, order_file:)
      if !reload && test('f', order_file)
        Plog.dump_info(reload:, nreload: !reload, order_file:)
        return true
      end
      sids = {}
      scontent = []
      `cat data/*.order | fgrep ",#{singer}," | sort -u`.split("\n").each do |l|
        fs = l.split(/,/)
        rsinger = fs[3]
        next unless singer == rsinger

        sid = fs[0].to_i.abs
        sids[sid] = true
        scontent << l
      end
      raise "No song found for #{singer}" unless sids.empty?

      Plog.info("Collect #{sids.size} songs for #{singer}")

      ssinfo = {}
      Dir.glob('data/list_content-*.yml').each do |afile|
        next unless afile =~ /list_content-\d+.yml$/

        Plog.info("Loading #{afile}")
        YAML.load_file(afile)[:content].each do |sinfo|
          # Plog.dump_info(sinfo:sinfo)
          ssinfo[sinfo[:song_id]] = sinfo if sids[sinfo[:song_id]]
        end
      end

      lcontent_file = "data/list_content-#{singer}.yml"
      File.open(lcontent_file, 'w') do |fod|
        fod.puts({
          id:      singer,
          content: ssinfo.values,
        }.to_yaml)
      end

      File.open(order_file, 'w') do |fod|
        fod.puts scontent.join("\n")
      end
      true
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  PlayList.handle_cli(
    ['--channel', '-C', 1],
    ['--key',     '-k', 1]
  )
end
