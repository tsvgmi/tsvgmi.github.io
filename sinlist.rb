#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/etc/toolenv"
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'sinatra/partial'
require 'yaml'
require 'net/http'
require 'core'
require 'listhelper'
require 'sequel'

set :bind, '0.0.0.0'
#ENV['DB_URL'] ||= 'playlist:playlistpasswd@tvuong-aws.colo29zuu6uk.us-west-2.rds.amazonaws.com'
ENV['DB_MY']  ||= 'playlist:playlistpasswd@127.0.0.1/Playlist'
ENV['DB_HAC'] ||= 'thienv:hBQufu5wegkK2Cay@13.250.100.224/hac_local'
#ENV['DB_HAC'] ||= 'playlist:playlistpasswd@127.0.0.1/hopamchuan'

HAC_DB           = Sequel.connect("mysql2://#{ENV['DB_HAC']}")
Sequel::Model.db = Sequel.connect("mysql2://#{ENV['DB_MY']}")
#HAC_DB = Sequel.connect('mysql2://playlist:playlistpasswd@127.0.0.1/hopamchuan')

require Dir.pwd + '/bin/dbmodels'

get '/' do
  "Hello Nothing"
end

get '/what' do
  "Hello what"
end

get '/fragment_upload/:user_name/:song_id/:song_name' do |user_name, song_id, song_name|
  locals = params.dup
  haml :fragment_upload, locals:locals
end

get '/list/:event' do |event|
  haml :list, locals: {event: event}, layout:nil
end

get '/playorder/:listname' do |listname|
  order_file = listname + "-order.txt"
  list_info  = HAC_DB[:tbl_playlists].first(id:listname.to_i)
  list_info.update(JSON.parse(list_info[:_post_user])) if list_info[:_post_user]
  if params[:reset] || !test(?f, order_file)
    sqlmain = "select sp.song_id, sp.playlist_id, s._title_ascii as song_ascii
         from tbl_songs_playlists as sp
         join tbl_songs as s on (sp.song_id = s.id) where sp.playlist_id=?"
    song_list = HAC_DB[sqlmain, listname].map {|r| [r[:song_id], r[:song_ascii]]}
    Plog.dump_info(song_list:song_list)
    File.open(order_file, "w") do |fod|
      song_list.each do |song_id, title|
        fod.puts "#{song_id},#{title},,,,,"
      end
    end
  end
  haml :playorder, locals:{order_file:order_file, list_info:list_info}
end

post '/playorder' do
  Plog.dump_info(params:params)
  list_id = params[:list_id]
  if params[:Reset]
    redirect "/playorder/#{list_id}?reset=true"
  else
    order_file = list_id + "-order.txt"
    File.open(order_file, "w") do |fod|
      fod.puts params[:slink]
    end
    redirect "/playorder/#{list_id}"
  end
end

get '/perflist/:user' do |user|
  if user =~ /^\d+$/
    sql_pl = "select u.id,u.username,p.* from tbl_users as u
           join tbl_playlists as p on (p.user_id=u.id)
           where u.id=? and _total_song_count>0
           order by create_date desc limit 30"
    playlists = HAC_DB[sql_pl, user.to_i].map {|r| r}
  else
    sql_pl = "select u.id,u.username,p.* from tbl_users as u
           join tbl_playlists as p on (p.user_id=u.id)
           where username=? and _total_song_count>0
           order by create_date desc limit 30"
    playlists = HAC_DB[sql_pl, user].map {|r| r}
  end
  if playlists.size <= 0
    return [403, "No playlists found for user #{user}"]
  end
  if listno = params[:listno]
    listno = listno.to_i
    if false
      all_listno = playlists.map{|r| r[:id]}
      unless all_listno.include?(listno)
        raise "Playlist #{listno} does not belong to user #{user}"
      end
    end
  else
    listno = playlists[0][:id]
  end

  sqlmain = "select sp.song_id, sp.playlist_id, p.title as list_name,
         s._title as song_name, s._title_ascii as song_ascii, s._key as song_key,
         s._lyric as lyric, s._singers as singers, u.username as main_user
         from tbl_songs_playlists as sp
         join tbl_playlists as p on (sp.playlist_id = p.id)
         join tbl_songs as s on (sp.song_id = s.id)
         join tbl_users as u on (u.id = s.post_user_id)
         where p.id=?"
  sqlall = "select sp.song_id, sp.playlist_id, p.title as list_name, s._title as song_name,
         s._title_ascii as song_ascii, sr.key as song_key, sr.lyric, u.username
         from tbl_songs_playlists as sp 
         join tbl_playlists as p on (sp.playlist_id = p.id)
         join tbl_songs as s on (sp.song_id = s.id)
         join tbl_songs_contributes as sr on (sr.song_id = sp.song_id)
         left join tbl_users as u on (u.id = sr.user_id) where playlist_id=?"
  list_info  = HAC_DB[:tbl_playlists].first(id:listno.to_i)
  list_info.update(JSON.parse(list_info[:_post_user])) if list_info[:_post_user]
  order_file = "#{listno}-order.txt"
  order_list = {}
  if test(?f, order_file)
    lno = 0
    Plog.info(msg:"Loading #{order_file}")
    order_list = File.read(order_file).split("\n").map do |r|
      song_id, title, version, singer, skey, style, tempo = r.split(',')
      song_id = song_id.to_i
      rec = {
        song_id:    song_id,
        title:      title,
        version:    (version && !version.empty?) ? version : nil,
        singer:     singer,
        singer_key: skey,
        style:      style,
        tempo:      tempo,
        order:      lno,
      }
      lno += 1
      [song_id, rec]
    end
    order_list = Hash[order_list]
  end
  all_versions_set = {}
  HAC_DB[sqlall, listno].each do |r|
    key = "#{r[:song_ascii]}.#{r[:username]}"
    all_versions_set[key] = r
  end
  #Plog.dump_info(all_keys:all_versions_set.keys)
  song_list = HAC_DB[sqlmain, listno].map do |r|
    oinfo = order_list[r[:song_id]] || {}
    if version = oinfo[:version]
      key = "#{r[:song_ascii]}.#{version}"
      Plog.info("Checking #{key}")
      if ainfo = all_versions_set[key]
        Plog.dump_info(msg:'Replacing main version', ainfo:ainfo)
        r.update({
          song_key: ainfo[:song_key],
          lyric:    ainfo[:lyric],
          username: ainfo[:username],
        })
        unless r[:song_key]
          # Override version, but version does not have key
          if r[:lyric] =~ /\[([^\]]+)\]/
            song_key = $1
            r[:song_key] = song_key
          end
        end
      end
    else
      # If default, I don't rely on DB field.  Calculate from lyric
      if r[:lyric] =~ /\[([^\]]+)\]/
        song_key = $1
        r[:song_key] = song_key
      end
    end
    r
  end.sort_by {|r|
    oinfo = order_list[r[:song_id]] || {}
    oinfo[:order] || 9999
  }

  song_ids = song_list.map{|r| r[:song_id]}
  sql_artists = "select sp.id as perf_id, sp.song_id, sp.key, sp.link,
                 group_concat(ar.name) as artist from tbl_songs_singers as ss
                 join tbl_artists as ar on (ss.artist_id = ar.id)
                 join tbl_songs_performs as sp on (sp.song_id = ss.song_id)
                 where ss.song_id in ? group by perf_id"

  artist_set = HAC_DB[sql_artists, song_ids].map{|r| r}.group_by {|r| r[:song_id]}
  #Plog.dump_info(artist_set:artist_set, song_ids:song_ids)

  plist_file      = "#{user}.plist"
  perf_info       = test(?f, plist_file) ? YAML.load_file(plist_file) : {}
  singer_profiles = YAML.load_file('singer-profile.yml')
  haml :perflist, locals: {list_info:list_info, song_list:song_list, user:user,
                           order_list:order_list, artist_set:artist_set,
                           playlists:playlists, perf_info:perf_info,
                           singer_profiles:singer_profiles}
end

get '/program/:event' do |event|
  ord_list   = YAML.load_file("#{event}.order")
  song_list  = YAML.load_file("#{event}.slist")
  song_store = load_songs(ord_list, song_list)
  performers = []
  styles     = []
  ord_list.each_with_index do |asection, sec_no|
    (asection['list'] || []).each do |aname|
      aname, asinger = aname.split(',')
      sentry = song_store[aname]
      next unless sentry
      #Plog.dump_info(sentry:sentry.keys)
      if sentry[:singer]
        performers += sentry[:singer].force_encoding('UTF-8').split(/\s*,\s*/)
      end
      if sentry[:style]
        styles << sentry[:style].downcase
      end
    end
  end
  performers = performers.sort.uniq
  styles     = styles.sort.uniq
  #Plog.dump_info(performers:performers, styles:styles)
  haml :program, locals: {ord_list:ord_list, song_store:song_store,
                          performers:performers, styles:styles}
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
end
