#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/etc/toolenv"
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'sinatra/partial'
require 'sinatra/flash'
require 'json'
require 'yaml'
require 'net/http'
require 'core'
require 'sequel'
require 'better_errors'
require 'rdiscount'

require 'listhelper'
require 'playlist'

require_relative '../hacauto/bin/hac-nhac'
require_relative '../hacauto/bin/hac-nhac'

set :bind, '0.0.0.0'

enable :sessions

#configure :development do
  #use BetterErrors::Middleware
  #BetterErrors.application_root = __dir__
#end

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

not_found do
  path = request.env['PATH_INFO']
  mdkfile = "#{settings.views}/#{path}.mdk"
  mdfile = "#{settings.views}/#{path}.md"
  if test(?f, mdkfile)
    eresult = ERB.new(File.read(mdkfile)).result(binding)
    result  = RDiscount.new(eresult).to_html
    return [200, result]
  elsif test(?f, mdfile)
    eresult = File.read(mdfile)
    result  = RDiscount.new(eresult).to_html
    return [200, result]
  end
  return [404, "Page #{path} not found"]
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

get '/singer_list/:singer' do |singer|
  Plog.dump_info(singer:singer, params:params)
  if params[:listno] && !params[:listno].empty? && params[:listno] != singer
    Plog.info("Redirecting")
    redirect "/singer_list/#{params[:listno]}"
  end
  reload       = params[:reload].to_i
  locals       = PlayList.collect_for_singer(singer, reload:reload==2)
  singer_lists = PlayList.band_singers.map{|r| {name:r}}
  locals.update(user:'thienv', playlists:nil, singer_lists:singer_lists,
                note:nil)
  haml :perflist, locals: locals
end

get '/perflist/:user' do |user|
  Plog.dump_info(params:params)
  reload   = params[:reload].to_i
  locals   = PlayList.collect_for_user(user, params[:listno], reload == 2)
  listno   = locals[:listno]
  notefile = "data/#{listno}.notes"
  note     = nil
  if test(?f, notefile)
    note = markdown(File.read(notefile))
  end
  locals.update(user:user, note:note)
  haml :perflist, locals: locals
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

get '/smulelist2/:user' do |user|
  content   = []
  singer    = params[:singer]
  singers   = {}
  if false
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
  end
  haml :smulelist2, locals: {user:user, singer:singer, singers:singers}
end

get "/smule_data/:user" do |user|
  Plog.dump_info(params:params)
  singer    = (params[:singer] || "").split
  start     = params[:start].to_i
  length    = (params[:length] || 100).to_i
  order     = (params[:order] || {}).values.first || {'column'=>5, 'dir'=>'desc'}
  search    = (params[:search] || {})['value']
  Plog.dump_info(order:order)
  smcontent = SmContent.new(user)
  columns   = [:title, :isfav, :record_by, :listens, :loves, :created]
  data0     = smcontent.content.limit(length).offset(start)
  ocolumn   = order['column'].to_i
  if order['dir'] == 'desc'
    data0  = data0.reverse(columns[ocolumn])
  else
    data0  = data0.order(columns[ocolumn])
  end
  if search
    search = search.downcase
    data0 = data0.where(Sequel.lit("LOWER(stitle) like ? or LOWER(record_by) like ?",
                                   "%#{search}%", "%#{search}%"))
  end
  data1 = data0.map {|r|
    isfav_0     = r[:isfav] ? "<i class='fa fa-star'></i>" : ""
    href        = "https://www.smule.com"
    record_by_0 = r[:record_by].split(',').map{|n| "<a href='#{href}/#{n}' target='smule'>#{n}</a>"}.join(", ")
    avatar      = "<img class=savatar src=#{r[:avatar]} height=30 width=30></img>"
    title       = "<a href='#{href}#{r[:href]}' target='smule'>#{r[:title]}</a>"
    title_0     = "#{avatar}#{title}"
    [title_0, isfav_0, record_by_0, r[:listens], r[:loves], r[:created]]
  }
  data = {
    draw:            params[:draw],
    recordsTotal:    smcontent.content.count,
    recordsFiltered: data0.count,
    data:            data1,
  }
  data.to_json
end

get '/smulelist/:user' do |user|
  content   = []
  singer    = (params[:singer] || "").split
  tags      = (params[:tags] || "").split.join('|')
  tags      = tags.empty? ? nil : Regexp.new(tags)
  singers   = {}
  smcontent = SmContent.new(user)
  records   = smcontent.content.left_join(smcontent.songtags, name: :stitle).
    reverse(:created)
  records.each do |r|
    record_by = r[:record_by].split(',')
    if singer.size > 0
      next unless (record_by & singer).size > 0
    end
    if tags
      next unless r[:tags] =~ tags
    end
    content << r
    record_by.each do |asinger|
      singers[asinger] ||= {name:asinger, count:0, listens:0, loves:0, favs:0}
      singers[asinger][:count]   += 1
      singers[asinger][:listens] += (r[:listens] || 0)
      singers[asinger][:loves]   += r[:loves]
      if r[:isfav] || r[:oldfav]
        singers[asinger][:favs] += 1
      end
    end
  end
  # Front end will also do sort, but we do on backend so content would
  # not change during initial display
  content = content.sort_by {|r| r[:sincev].to_f }
  singers = singers.values.sort_by {|r| r[:count]}.reverse
  #Plog.dump_info(all_singers:smcontent.singers.count)
  haml :smulelist, locals: {user:user, content:content, singers:singers,
                            all_singers:smcontent.singers,
                            join_me:smcontent.join_me,
                            i_join:smcontent.i_join}
end

get '/smulegroup/:user' do |user|
  content   = []
  singer    = (params[:singer] || "").split
  tags      = (params[:tags] || "").split.join('|')
  tags      = tags.empty? ? nil : Regexp.new(tags)
  smcontent = SmContent.new(user)
  records   = smcontent.content.left_join(smcontent.songtags, name: :stitle).
    reverse(:created)
  records.each do |r|
    if singer.size > 0
      record_by = r[:record_by].split(',')
      next unless (record_by & singer).size > 0
    end
    if params[:title] && r[:title] != params[:title]
      next
    end
    if tags
      next unless r[:tags] =~ tags
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
  def render_mdk(template, options={})
    # Save a local copy as I can't control if haml is going to
    # mess with the definition
    locals = options[:locals] || {}
    page_out = haml(:layout, options) do
      mdkfile = "#{settings.views}/#{template}.mdk"
      if test(?f, mdkfile)
        bind = binding
        locals.each do |k, v|
          bind.local_variable_set(k, v)
        end
        eresult = ERB.new(File.read(mdkfile)).result(bind)
        result  = RDiscount.new(eresult).to_html
      else
        raise "Template mdk #{template} not found"
      end
      result
    end
    return [200, page_out]
  end

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
   "#{ENV['HOME']}/shared/#{fname}"].each do |afile|
    Plog.dump_info(afile:afile, fname:fname)
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
        Integer :account_id, unique:true
        String  :name, unique: true, null: false
        String  :avatar
        String  :following
        String  :follower
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
        String  :stitle
        String  :avatar
        String  :href
        String  :record_by
        Boolen  :is_ensemble
        Boolen  :isfav
        Boolen  :oldfav
        String  :collab_url
        String  :play_path
        String  :parent
        String  :orig_city
        Integer :listens
        Integer :loves
        Integer :gifts
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
      @DB      ||= create_db_and_schemas
      content_file  = search_data_file("content-#{user}.yml")
      songtags_file = search_data_file("songtags2.yml")
      if !@cur_user || (@cur_user != user) || (@load_time < File.mtime(content_file)) ||
          (@load_time < File.mtime(songtags_file))
        Plog.info("Loading db/cache for #{user}")
        contents = @DB[:contents]
        singers  = @DB[:singers]
        songtags = @DB[:songtags]

        contents.delete
        singers.delete
        songtags.delete

        YAML.load_file(content_file).each do |sid, sinfo|
          irec = sinfo.dup
          irec.delete(:m4tag)
          irec.delete(:media_url)
          if irec[:record_by].is_a?(Array)
            irec[:record_by] = irec[:record_by].join(',')
          end
          contents.insert(irec)
        end
        singers.delete
        YAML.load_file(search_data_file("singers-#{user}.yml")).each do |singer, sinfo|
          irec = sinfo.dup
          begin
            singers.insert(irec)
          rescue => errmsg
            Plog.dump_info(errmsg:errmsg, singer:singer, sinfo:sinfo)
          end
        end
        songtags.delete
        File.read(songtags_file).split("\n").each do |l|
          name, tags = l.split(':::')
          songtags.insert(name:name, tags:tags)
        end
        @cur_user  = user
        @load_time = Time.now
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
      solo_sel   = solo_idx.split('/').map{|f| f.to_i}
      @yk_videos = @yk_videos.values_at(*solo_sel).compact
      #Plog.dump_info(solo_sel:solo_sel, yk_videos:@yk_videos)
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

