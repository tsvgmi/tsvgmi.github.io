#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/etc/toolenv"
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'sinatra/partial'
require 'sinatra/flash'
require 'yaml'
require 'net/http'
require 'core'
require 'listhelper'
require 'sequel'
require 'better_errors'
require_relative '../hacauto/bin/hac-nhac'

set :bind, '0.0.0.0'

enable :sessions

configure :development do
  use BetterErrors::Middleware
  BetterErrors.application_root = __dir__
end

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# routes...
options "*" do
  response.headers["Allow"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token"
  response.headers["Access-Control-Allow-Origin"] = "*"
  200
end

get '/fragment_upload/:user_name/:song_id/:song_name' do |user_name, song_id, song_name|
  locals = params.dup
  haml :fragment_upload, locals:locals
end

post '/song-style' do
  #Plog.dump_info(params:params)
  user      = params[:user]
  song_id   = params[:song_id]
  song_name = params[:song_name]
  pnote     = PlayNote.new(user)
  uperf_info = {
    instrument:params[:instrument], key:params[:key],
    intro:params[:intro],
    ytvideo:params[:ytvideo],   vidkey:params[:vidkey],
    ytkvideo:params[:ytkvideo], ytkkey:params[:ytkkey],
    smkey:params[:smkey],       smule:params[:smule],
    nctkey:params[:nctkey],     nct:params[:nct],
  }
  pnote.replace(song_id, song_name, uperf_info)
  flash[:notice] = "Style for #{song_name} replaced"
  redirect "/song-style/#{user}/#{song_id}/#{song_name}"
end

get '/song-style/:user/:song_id/:song_name' do |user, song_id, song_name|
  uperf_info = PlayNote.new(user)[song_name] || {}
  song_id    = song_id.to_i
  song_info  = SongInfo.new(song_id).content
  locals     = {user:user, song_id:song_id, song_name:song_name,
                uperf_info:uperf_info, song_info:song_info}
  #Plog.dump_info(locals:locals)
  haml :song_style, locals:locals
end

get '/play-here' do
  ofile = params[:ofile]
  Plog.dump_info(ofile:ofile)
  if test(?f, ofile)
    system("open \"#{ofile}\"")
  end
end

get '/list/:event' do |event|
  haml :list, locals: {event: event}, layout:nil
end

get '/playorder/:user/:listno' do |user, listno|
  playlists  = PlayList.for_user(user)
  list_info  = playlists.find{|r| r[:id] == listno.to_i}
  play_order = PlayOrder.new(listno)
  #Plog.dump_info(playlists:playlists, list_info:list_info)
  if params[:reset]
    play_order.create_file
  elsif params[:refresh]
    play_order.refresh_file
  end
  haml :playorder, locals:{play_order:play_order, list_info:list_info}
end

post '/playorder' do
  #Plog.dump_info(params:params)
  list_id = params[:list_id]
  user    = params[:user]
  if params[:Reset]
    redirect "/playorder/#{user}/#{list_id}?reset=true"
  elsif params[:Refresh]
    redirect "/playorder/#{user}/#{list_id}?refresh=true"
  else
    PlayOrder.new(list_id).write_file(params[:slink])
    redirect "/playorder/#{user}/#{list_id}"
  end
end

get '/playlist' do
  haml :playlist_index
end

get '/perflist/:user' do |user|
  reload = params[:reload].to_i
  Plog.dump_info(params:params, reload:reload)
  playlists = PlayList.for_user(user, reload == 2)
  if playlists.size <= 0
    return [403, "No playlists found for user #{user}"]
  end

  if listno = params[:listno]
    listno = listno.to_i
  else
    listno = playlists[0][:id]
  end

  list_info  = playlists.select{|r| r[:id] == listno}.first
  poptions   = {range:params[:range]}
  play_order = PlayOrder.new(listno, poptions)
  order_list = Hash[play_order.content_str]
  song_list  = play_order.fetch_songs
  singers    = play_order.singers
  perf_info  = PlayNote.new(user)
  haml :perflist, locals: {list_info:list_info, song_list:song_list, user:user,
                           order_list:order_list, singers:singers,
                           playlists:playlists, perf_info:perf_info}
end

get '/send_patch/:pstring' do |pstring|
  command = "bk50set.rb apply_midi #{pstring}"
  if key = params[:key]
    command += " --key #{key}" unless key.empty?
  end
  Plog.info(command)
  presult = JSON.parse(`#{command}`)
  haml :patch_info, locals: {presult:presult}, layout:nil
end

get '/poke/:command' do |command|
  `#{command} 2>&1`
end

get '/smremove/:user/:sid' do |user, sid|
  SmContent.new(user).remove(sid)
  redirect "/smulelist/#{user}"
end

get '/smulelist/:user' do |user|
  content   = []
  singer    = (params[:singer] || "").split
  singers   = {}
  smcontent = SmContent.new(user)
  records   = smcontent.content
  records.each do |r|
    record_by = r[:record_by].split(',')
    if singer.size > 0
      next unless (record_by & singer).size > 0
    end
    if params[:title] && r[:title] != params[:title]
      next
    end
    content << r
    record_by.each do |asinger|
      singers[asinger] ||= {name:asinger, count:0, listens:0, loves:0}
      singers[asinger][:count]   += 1
      singers[asinger][:listens] += (r[:listens] || 0)
      singers[asinger][:loves]   += r[:loves]
    end
  end
  # Front end will also do sort, but we do on backend so content would
  # not change during initial display
  content = content.sort_by {|r| r[:sincev].to_f }
  singers = singers.values.sort_by {|r| r[:count]}.reverse
  Plog.dump_info(all_singers:smcontent.singers.count)
  haml :smulelist, locals: {user:user, content:content, singers:singers,
                            all_singers:smcontent.singers,
                            join_me:smcontent.join_me,
                            i_join:smcontent.i_join}
end

get '/smulegroup/:user' do |user|
  content   = []
  singer    = (params[:singer] || "").split
  smcontent = SmContent.new(user)
  records   = smcontent.content
  records.each do |r|
    if singer.size > 0
      record_by = r[:record_by].split(',')
      next unless (record_by & singer).size > 0
    end
    if params[:title] && r[:title] != params[:title]
      next
    end
    content << r
  end
  scontent = content.group_by{|r| r[:title].downcase.sub(/\s*\(.*$/, '')}
  haml :smulegroup, locals: {user:user,  scontent:scontent,
                            all_singers: smcontent.singers,
                            songtags:    smcontent.songtags}
end

get '/dl-transpose/:video' do |video|
  offset = params[:offset].to_i
  download_transpose(video, offset, params)
end

get '/reload-song/:song_id' do |song_id|
  files = Dir.glob("data/SONGS/song:#{song_id}:*")
  Plog.dump_info(files:files)
  FileUtils.rm(files, verbose:true)
end

helpers do
  def download_transpose(video, offset, options)
    require 'tempfile'

    Plog.dump_info(options:options)
    url   = "https://www.youtube.com/watch?v=#{video}"
    odir  = options[:odir]  || 'data/MP3'
    ofile = options[:title] || '%(title)s-%(creator)s-%(release_date)s'
    key   = params[:key] || offset
    ofile = "#{odir}/#{ofile}=#{video}=#{key}"
    if test(?s, "#{ofile}.mp3")
      Plog.info("#{ofile}.mp3 already exist.  Skip download")
      return
    end
    tmpf  = Tempfile.new('youtube')
    ofmt  = "#{ofile}-pre.%(ext)s"
    command = "youtube-dl --extract-audio --audio-format mp3 --audio-quality 0 --embed-thumbnail"
    command += " -o '#{ofmt}' '#{url}'"
    system "set -x; #{command}"

    start = options[:start].to_i
    if (offset != 0) || (start > 0)
      command = "sox #{ofile}-pre.mp3 #{ofile}.mp3"
      command += " pitch #{offset}00" if offset != 0
      command += " trim #{options[:start]}" if start > 0
      command += "; rm -f #{ofile}-pre.mp3"
    else
      command = "mv #{ofile}-pre.mp3 #{ofile}.mp3"
    end
    system "set -x; #{command}"
  end


  KeyPos = %w(A A#|Bb B C C#|Db D D#|Eb E F F#|Gb G G#|Ab)
  # Attach play note to the like star
  def key_offset(base_key, new_key, closer=false)
    if !base_key || !new_key || base_key.empty? || new_key.empty?
      Plog.dump_info(msg:'No key', base_key:base_key, new_key:new_key)
      return 0
    end
    base_key = base_key.sub(/m$/, '')
    new_key  = new_key.sub(/m$/, '')
    #Plog.info({base_key:base_key, new_key:new_key}.inspect)
    new_offset = KeyPos.index{|f| new_key =~ /^#{f}$/}
    base_offset = KeyPos.index{|f| base_key =~ /^#{f}$/}
    if !new_offset || !base_offset
      if new_key && !new_key.empty?
        Plog.dump_info(msg:'No key offset', base_key:base_key, new_key:new_key)
      end
      return 0
    end
    offset = new_offset - base_offset
    offset += 12 if offset < 0
    # Keep offfset close for vis
    if closer
      offset -= 12 if offset >= 6
    end
    offset
  end
  
  # For flashcard - memorize.
  def clean_and_split(lyric, position)
    result = []
    lyric.gsub(/\s*\r/, '').gsub(/^---/, '<hr/>').split("\n").each do |l|
      words = l.gsub(/<span.*?<\/span>/, '').split.
                map{|w| w.sub(/\([^\)]*\)/, '')}.
                reject{|w| w.empty?}
      position += 1 if words[0].include?(':')
      span1 = "#{words[0..position-1].join(' ')}"
      span2 = "#{(words[position..-1] || []).join(' ')}"
      result << [span1, span2]
    end
    result
  end
end

def search_data_file(fname)
  ["/Volumes/Voice/SMULE/#{fname}",
   "#{ENV['HOME']}/#{fname}"].each do |afile|
    if test(?r, afile)
      return afile
    end
  end
  nil
end

class DBCache
  class << self
    attr_reader :DB

    def create_db_and_schemas
      @DB = Sequel.sqlite
      @DB.create_table :singers do
        primary_key :id
        String :name, unique: true, null: false
        String :avatar
        String :following
        String :follower
      end
      @DB.create_table :songtags do
        primary_key :id
        String :name, unique: true, null: false
        String :tags
      end
      @DB.create_table :contents do
        primary_key :id
        String  :sid, unique: true, null: false
        String  :title
        String  :avatar
        String  :href
        String  :record_by
        Boolen  :is_ensemble
        Boolen  :isfav
        Boolen  :oldfav
        String  :collab_url
        String  :play_path
        String  :parent
        Integer :listens
        Integer :loves
        String  :ofile
        String  :sfile
        String  :since
        Float   :sincev
        Date    :created
        Date    :updated_at
      end
      @DB
    end

    def load_db_for_user(user)
      @uloaded ||= {}
      @DB      ||= create_db_and_schemas
      content_file = search_data_file("content-#{user}.yml")
      if !@uloaded[user] || (@uloaded[user] < File.mtime(content_file))
        Plog.info("Loading db/cache for #{user}")
        contents = @DB[:contents]
        singers  = @DB[:singers]
        songtags = @DB[:songtags]

        contents.delete
        YAML.load_file(content_file).each do |sid, sinfo|
          irec = sinfo.dup
          irec.delete(:m4tag)
          if irec[:record_by].is_a?(Array)
            irec[:record_by] = irec[:record_by].join(',')
          end
          contents.insert(irec)
        end
        singers.delete
        YAML.load_file(search_data_file("singers.yml")).each do |singer, sinfo|
          irec = sinfo.dup
          singers.insert(irec)
        end
        songtags.delete
        File.read(search_data_file("songtags.yml")).split("\n").each do |l|
          name, tags = l.split(':::')
          songtags.insert(name:name, tags:tags)
        end
        @uloaded[user] = Time.now
      end
    end
  end
end

class SmContent
  attr_reader :join_me, :i_join

  def content
    DBCache.DB[:contents]
  end

  def singers
    DBCache.DB[:singers]
  end

  def songtags
    DBCache.DB[:songtags]
  end

  def initialize(user)
    @user    = user
    @join_me = {}
    @i_join  = {}

    DBCache.load_db_for_user(user)
    DBCache.DB[:contents].where(Sequel.lit("record_by like '%#{user}%'")).
      each do |r|
      rby = r[:record_by].split(',')
      if rby[0] == user
        other = rby[1]
        @join_me[other] ||= 0
        @join_me[other] += 1
      end
      if rby[1] == user
        other = rby[0]
        @i_join[other] ||= 0
        @i_join[other] += 1
      end
    end
  end

  def remove(sid)
    unless content.where(sid:sid)
      Plog.info("Cannot locate #{sid} - #{@content.size}")
      return true
    end
    Plog.info("Deleting #{sid}")
    content.where(sid:sid).delete
    if afile = search_data_file("content-#{@user}.yml")
      Plog.info("Updating #{afile}")
      scontent = {}
      content.each do |r|
        scontent[r[:sid]] = r
      end
      #Plog.dump_info(content:content)
      File.open(afile, 'w') do |fod|
        fod.puts scontent.to_yaml
      end
    end
    true
  end
end

class PlayNote
  attr_reader :info

  def initialize(user)
    @plist_file = "data/#{user}-plist.json"
    @info       = test(?f, @plist_file) ?
      JSON.parse(File.read(@plist_file), symbolize_names:true) : {}
  end

  def [](song_name)
    res = @info[song_name.to_sym]
    res
  end

  def replace(song_id, song_name, entry)
    require 'tempfile'
    require 'fileutils'

    @info[song_name.to_sym] = entry

    # Safer write
    tmpf = Tempfile.new("plist")
    tmpf.puts JSON.pretty_generate(@info)
    tmpf.close
    #Plog.dump_info(ofile:@plist_file, info:@info)
    FileUtils.move(tmpf.path, @plist_file, verbose:true, force:true)
  end
end

class PlayList
  HAC_URL = "https://hopamchuan.com"

  def initialize(list_info)
    if list_info.is_a?(Hash)
      listno    = list_info[:id]
      @save_list = list_info.clone
    else
      listno    = list_info.to_i
      @save_list = {id: listno}
    end
    @list_id = listno
  end

  def fetch(fetch_new=false)
    cfile = "data/list_content-#{@list_id}.yml"
    if !fetch_new && test(?s, cfile)
      @save_list = YAML.load_file(cfile)
    else
      @save_list[:content] = HacSource.new.playlist("#{HAC_URL}/playlist/v/#{@list_id}")
      File.open(cfile, "w") do |fod|
        fod.puts @save_list.to_yaml
      end
      @save_list
    end
    @save_list
  end

  def self.for_user(user, reload=false)
    cfile = "data/list_for_user-#{user}.yml"
    if !reload && test(?s, cfile)
      ulist = YAML.load_file(cfile)
    else
      ulist = HacSource.new.list_for_user("#{HAC_URL}/profile/playlists/#{user}")
      File.open(cfile, "w") do |fod|
        fod.puts ulist.to_yaml
      end
      ulist
    end
  end
end

class PlayOrder
  attr_reader :playlist, :content_str

  def self.hac_song_info(url)
    sf = url.split('/')
    sid, sname, version = sf[4], sf[5], sf[6]
    cfile = "data/SONGS/song:#{sid}:#{version}:#{sname}"

    if test(?s, cfile)
      sinfo = YAML.load_file(cfile)
    else
      sinfo = HacSource.new.lyric_info(url)
      File.open(cfile, "w") do |fod|
        fod.puts sinfo.to_yaml
      end
      sinfo
    end
    sinfo
  end

  def initialize(list_info, options={})
    @list_id    = list_info.is_a?(Hash) ? list_info[:id] : list_info.to_i
    @order_file = "data/#{@list_id}.order"
    @playlist   = PlayList.new(list_info)
    if test(?f, @order_file)
      @content_str = _content_str
      if options[:range]
        rstart, rend = options[:range].split(',')
        @content_str = @content_str[rstart.to_i..rend.to_i]
      end
    else
      create_file
    end
  end

  def singers(active=true)
    @content_str.select {|sid, sinfo| sinfo[:active]}.map do |sid, sinfo|
      sinfo[:singer]
    end.compact.uniq.sort
  end

  def self.all_references
    wset = {}
    Dir.glob("data/*.order").each do |afile|
      File.read(afile).split("\n").each do |aline|
        next if aline =~ /^\s*#/
        key, *values = aline.chomp.sub(/,+$/, '').split(',')
        #Plog.dump_info(afile:afile, key:key, values:values)
        if values.size >= 3
          wset[key.to_i] ||= []
          wset[key.to_i] << "#{key},#{values.join(',')}"
          #Plog.dump_info(afile:afile, key:key, values:values)
        end
      end
    end
    wset
  end

  def create_file
    test(?f, @order_file) && File.delete(@order_file)
    wset   = self.class.all_references
    #Plog.dump_info(wset:wset.keys)
    output = []
    @playlist.fetch[:content].sort_by{|r| r[:name]}.each do |r|
      Plog.dump_info(r:r)
      fs = r[:href].split('/')
      if wset[r[:song_id]]
        Plog.dump_info(previous:wset[r[:song_id]])
        output.concat(wset[r[:song_id]])
      else
        output << "#{r[:song_id]},#{fs[5]},,,,,,,"
      end
    end
    write_file(output.join("\n"))
  end

  def fetch_song_list
    qorder = @content_str.map{|r| r[0]}
    @playlist.fetch[:content].select do |asong|
      qorder.include?(asong[:song_id])
    end.sort_by do |asong|
      qorder.index(asong[:song_id])
    end
  end

  def fetch_songs
    order_list = Hash[@content_str]
    fetch_song_list.map do |asong|
      oinfo = order_list[asong[:song_id]]
      url   = asong[:href].sub(/\/*$/, '')
      #Plog.dump_info(url:url)
      if oinfo[:version] && !oinfo[:version].empty?
        url += "/#{oinfo[:version]}"
      end
      asong.update(self.class.hac_song_info(url))
    end
  end

  def content
    test(?f, @order_file) ? File.read(@order_file) : ''
  end

  def _content_str
    unless test(?f, @order_file)
      return {}
    end
    lno        = 0
    order_list = []
    Plog.info(msg:"Loading #{@order_file}")
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
        song_id:    song_id,
        title:      title,
        version:    (version && !version.empty?) ? version : nil,
        singer:     singer,
        singer_key: skey,
        style:      style,
        tempo:      tempo,
        lead:       lead,
        order:      lno,
        solo_idx:   solo_idx,
        active:     active,
      }
      lno += 1
      order_list << [song_id, rec]
    end
    #Plog.dump_info(order_list:order_list)
    order_list
  end

  def refresh_file
    song_list = @playlist.fetch(true)[:content].group_by {|r| r[:song_id]}
    wset      = {}
    output    = []
    Plog.info("Refresh data")
    read_file.each do |l|
      sno, _title, _version, singer, skey, _remain   = l.split(',', 6)
      if song_list[sno.to_i.abs]
        output << l
        song_list.delete(sno.to_i.abs)
      end
    end
    wset      = self.class.all_references
    output += song_list.map do |sid, recs|
      sname = recs[0][:href].split('/')[5]
      if wset[sid]
        Plog.dump_info(previous:wset[sid])
        wset[sid].first
      else
        if Dir.glob("thienv/#{sid}:*").size > 0
          version = 'thienv'
        else
          version = ''
        end
        "#{sid},#{sname},#{version},,,,"
      end
    end
    write_file(output.join("\n"))
  end

  def read_file
    if test(?f, @order_file)
      File.read(@order_file).split("\n").select {|l| l !~ /^\s*#/}
    else
      []
    end
  end

  def write_file(new_content)
    File.open(@order_file, "w") do |fod|
      fod.puts "# song_id,title,version,singer,skey,style,tempo,lead,solo_idx"
      fod.puts new_content
    end
    @content_str = _content_str
  end
end

class SongInfo
  attr_reader :content

  def initialize(song_id, version=nil)
    if version
      fptn = "data/SONGS/song:#{song_id}:#{version}:*"
    else
      fptn = "data/SONGS/song:#{song_id}:{,*}:*"
    end
    @content = {}
    if sfile = Dir.glob(fptn)[0]
      if !test(?s, sfile)
        Plog.dump_error(msg:'File not found', sfile:sfile)
      else
        @content = YAML.load_file(sfile)
      end
    end
  end
end

class VideoInfo
  attr_reader :videos, :yk_videos

  def initialize(vstring, kstring=nil)
    yvideos = (vstring || "").split('|')
    vidkeys = (kstring || "").split('|')
    @yk_videos = yvideos.zip(vidkeys)
    check_videos
  end

  # Select set is "1/2/3"
  # If there is one or more solo index specified.  Use it since same song 
  # could be played in multiple styles
  def select_set(solo_idx)
    if solo_idx && @yk_videos.size > 0
      solo_sel  = solo_idx.split('/').map{|f| f.to_i}
      @yk_videos  = @yk_videos.values_at(*solo_sel).compact
      check_videos
    end
    @yk_videos
  end

  def check_videos
    @videos = []
    @yk_videos.each do |svideo, skey|
      video, *ytoffset = svideo.split(',')
      ytoffset.each_slice(2) do |ytstart, ytend|
        if ytstart =~ /:/
          ytstart = $`.to_i*60 + $'.to_i
        end
        if ytend =~ /:/
          ytend   = $`.to_i*60 + $'.to_i
        end
        vid = "video_#{video.gsub(/[^a-z0-9_]/i, '')}_#{ytstart}_#{ytend}"
        #Plog.dump_info(vid:vid)
        @videos << {
          vid:   vid,
          video: video,
          start: ytstart.to_i, end: ytend.to_i, key: skey
        }
      end
    end
  end
end

