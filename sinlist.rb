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
#ENV['DB_URL'] ||= 'playlist:playlistpasswd@tvuong-aws.colo29zuu6uk.us-west-2.rds.amazonaws.com'
#ENV['DB_MY']  ||= 'playlist:playlistpasswd@127.0.0.1/Playlist'
#ENV['DB_HAC'] ||= 'playlist:playlistpasswd@127.0.0.1/hopamchuan'

DB = Sequel.connect('sqlite://sinlist.db')

if false
HAC_DB           = Sequel.connect('mysql2://thienv:hBQufu5wegkK2Cay@13.250.100.224/hac_local')
HAC_DB2          = Sequel.connect('mysql2://thienv:hBQufu5wegkK2Cay@13.250.100.224/playlist')
end

#Sequel::Model.db = Sequel.connect("mysql2://#{ENV['DB_MY']}")
#HAC_DB = Sequel.connect('mysql2://playlist:playlistpasswd@127.0.0.1/hopamchuan')

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
    ytvideo:params[:ytvideo], vidkey:params[:vidkey],
    smkey:params[:smkey],     smule:params[:smule],
    nctkey:params[:nctkey],   nct:params[:nct],
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
  play_order = PlayOrder.new(listno)
  order_list = Hash[play_order.content_str]
  song_list  = play_order.fetch_songs
  perf_info  = PlayNote.new(user)
  haml :perflist, locals: {list_info:list_info, song_list:song_list, user:user,
                           order_list:order_list, 
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
  records.each do |sid, r|
    if singer.size > 0
      next unless (r[:record_by] & singer).size > 0
    end
    if params[:title] && r[:title] != params[:title]
      next
    end
    content << r
    r[:record_by].each do |asinger|
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
  Plog.dump_info(all_singers:smcontent.singers.size)
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
  records.each do |sid, r|
    if singer.size > 0
      next unless (r[:record_by] & singer).size > 0
    end
    if params[:title] && r[:title] != params[:title]
      next
    end
    content << r
  end
  scontent = content.group_by{|r| r[:title].downcase.sub(/\s*\(.*$/, '')}
  haml :smulegroup, locals: {user:user, scontent:scontent,
                            all_singers:smcontent.singers}
end

helpers do
  KeyPos = %w(A A#|Bb B C C#|Db D D#|Eb E F F#|Gb G G#|Ab)
  # Attach play note to the like star
  def key_offset(base_key, new_key)
    if !base_key || !new_key
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

class SmContent
  attr_reader :content, :singers, :join_me, :i_join

  def initialize(user)
    @user    = user
    @join_me = {}
    @i_join  = {}
    cfile    = nil
    ["/Volumes/Voice/SMULE/content-#{@user}.yml",
     "#{ENV['HOME']}/content-#{@user}.yml"].each do |afile|
      if test(?r, afile)
        cfile = afile
        break
      end
    end

    unless cfile
      raise "Cannot locate content file to load for #{user}"
    end
    @content = YAML.load_file(cfile)
    @content.each do |href, r|
      case v = r[:since]
      when /(min|m)$/
        r[:sincev] = v.to_i / 60.0
      when /hr?$/
        r[:sincev] = v.to_i
      when /d$/
        r[:sincev] = v.to_i * 24
      when /mo$/
        r[:sincev] = v.to_i * 24 * 30
      when /yr$/
        r[:sincev] = v.to_i * 24 * 365
      end
      r[:sid] ||= File.basename(r[:href])
      if r[:record_by][0] == user
        other = r[:record_by][1]
        @join_me[other] ||= 0
        @join_me[other] += 1
      end
      if r[:record_by][1] == user
        other = r[:record_by][0]
        @i_join[other] ||= 0
        @i_join[other] += 1
      end
    end

    @singers = {}
    ["/Volumes/Voice/SMULE/singers.yml",
     "#{ENV['HOME']}/singers.yml"].each do |afile|
      if test(?r, afile)
        @singers = YAML.load_file(afile)
        break
      end
    end
  end

  def remove(sid)
    unless @content[sid]
      Plog.info("Cannot locate #{sid} - #{@content.size}")
      return true
    end
    Plog.info("Deleting #{sid}")
    @content.delete(sid)
    ["/Volumes/Voice/SMULE/content-#{@user}.yml",
     "#{ENV['HOME']}/content-#{@user}.yml"].each do |afile|
      if test(?f, afile)
        Plog.info("Updating #{afile}")
        File.open(afile, 'w') do |fod|
          fod.puts @content.to_yaml
        end
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
    else
      create_file
    end
  end

  def self.all_references
    wset = {}
    Dir.glob("data/*.order").each do |afile|
      File.read(afile).split("\n").each do |aline|
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
    Plog.dump_info(wset:wset.keys)
    output = []
    @playlist.fetch[:content].sort_by{|r| r[:name]}.each do |r|
      Plog.dump_info(r:r)
      fs = r[:href].split('/')
      if wset[r[:song_id]]
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
    File.read(@order_file).split("\n").each do |r|
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
    if test(?f, @order_file)
      File.read(@order_file).split("\n").each do |l|
        sno, _title, _version, singer, skey, _remain   = l.split(',', 6)
        if song_list[sno.to_i.abs]
          output << l
          song_list.delete(sno.to_i.abs)
        end
      end
    end
    output += song_list.map do |sid, recs|
      sname = recs[0][:href].split('/')[5]
      if Dir.glob("thienv/#{sid}:*").size > 0
        version = 'thienv'
      else
        version = ''
      end
      "#{sid},#{sname},#{version},,,,"
    end
    write_file(output.join("\n"))
  end

  def write_file(new_content)
    File.open(@order_file, "w") do |fod|
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
    sfile = Dir.glob(fptn)[0]
    #Plog.dump_info(sfile:sfile)
    if !test(?s, sfile)
      Plog.dump_error(msg:'File not found', sfile:sfile)
      @content = {}
    else
      @content = YAML.load_file(sfile)
    end
  end
end
