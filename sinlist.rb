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
require_relative '../hacauto/bin/hac-nhac'

set :bind, '0.0.0.0'
#ENV['DB_URL'] ||= 'playlist:playlistpasswd@tvuong-aws.colo29zuu6uk.us-west-2.rds.amazonaws.com'
#ENV['DB_MY']  ||= 'playlist:playlistpasswd@127.0.0.1/Playlist'
#ENV['DB_HAC'] ||= 'playlist:playlistpasswd@127.0.0.1/hopamchuan'

if false
HAC_DB           = Sequel.connect('mysql2://thienv:hBQufu5wegkK2Cay@13.250.100.224/hac_local')
HAC_DB2          = Sequel.connect('mysql2://thienv:hBQufu5wegkK2Cay@13.250.100.224/playlist')
end

#Sequel::Model.db = Sequel.connect("mysql2://#{ENV['DB_MY']}")
#HAC_DB = Sequel.connect('mysql2://playlist:playlistpasswd@127.0.0.1/hopamchuan')

enable :sessions

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
    intro:params[:intro], ytvideo:params[:ytvideo],
    vidkey:params[:vidkey], smkey:params[:smkey],
    smule:params[:smule],
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

  #Plog.dump_info(list_info:list_info, song_list:song_list[0..5], _ofmt:'Y')

  perf_info       = PlayNote.new(user)
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

helpers do
  def load_songs(ord_list, song_flist)
    songs = []
    ord_list.each do |lpart|
      songs += (lpart['list'] || []).map{|se| se.split(',')[0]}
    end

    #Plog.dump_info(songs:songs)
    song_list   = Hash[Song.where(name_k:songs).as_hash(:name_k).
                       map{|k, v| [k, v.to_hash]}]
    sound_list  = Hash[Sound.where(name_k:songs).as_hash(:name_k, nil).
                       map{|k, v| [k, v.to_hash]}]
    #Plog.dump_info(song_list:song_list)
    
    ord_list.each do |lpart|
      (lpart['list'] || []).each do |sse|
        name_k, singer, key, style, tempo, kofs = sse.split(',')
        #Plog.dump_info(sse:sse, key:key, style:style)
        if song_list[name_k]
          song_list[name_k].update(singer:singer, key:key, style:style,
                                   tempo:tempo, kofs:kofs)
        else
          Plog.error("#{name_k} not found in song list")
        end
      end
    end

    song_list.each do |k, v|
      v.update(sound_list[k]) if sound_list[k]
    end
    #Plog.dump_info(song_list:song_list)
    song_list.each do |sname, sentry|
      path = (sentry[:lyric_url] || sentry[:href] || '').split('/')
      Plog.dump_info(path:path)
      if path.size >= 6
        sno, song, user = path[4], path[5], path[6]
        if user
          sfile = "/Users/tvuong/myprofile/#{user}/#{sno}::#{sname}.yml"
        else
          sfile = Dir.glob("/Users/tvuong/myprofile/*/#{sno}::#{sname}.yml")[0]
        end
        Plog.dump_info(sfile:sfile)
        if sfile && test(?s, sfile)
          flat = sentry[:kofs] =~ /f$/
          kofs = sentry[:kofs].to_i
          Plog.info "Transposing #{sfile}"
          sentry.update(ListHelper.transpose_song(sfile, kofs, flat:flat))
        else
          Plog.error("#{sfile} not found - source: #{sentry[:lyric_url]}")
        end
      end
    end
    song_list
  end

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

  def get_song_infos(song_ids)
    sql = "select ar.name as artist, ar.name_ascii, sp.key, sp.link, so.id
      as song_id,so._title, so._title_ascii from tbl_performs_singers as ps
      join tbl_artists as ar on (ar.id=ps.singer_id)
      join tbl_songs_performs as sp on (sp.id=ps.perform_id)
      join tbl_songs as so on (so.id=sp.song_id)
      where sp.song_id in ?"
    HAC_DB[sql, song_ids].map{|r| r}.group_by {|r| r[:song_id]}
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

  def initialize(list_info)
    @list_id    = list_info.is_a?(Hash) ? list_info[:id] : list_info.to_i
    @order_file = "data/#{@list_id}.order"
    @playlist   = PlayList.new(list_info)
    if test(?f, @order_file)
      @content_str = _content_str
    else
      create_file
    end
  end

  def create_file
    output = @playlist.fetch[:content].map do |r|
      Plog.dump_info(r:r)
      fs = r[:href].split('/')
      "#{r[:song_id]},#{fs[5]},,,,,"
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
      song_id, title, version, singer, skey, style, tempo, lead =
        r.split(',')
      next unless title
      song_id = song_id.to_i
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
        if song_list[sno.to_i]
          output << l
          song_list.delete(sno.to_i)
        end
      end
    end
    output += song_list.map do |sid, recs|
      sname = recs[0][:href].split('/')[5]
      "#{sid},#{sname},,,,,"
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
