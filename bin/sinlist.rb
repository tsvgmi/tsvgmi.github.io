#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "#{File.dirname(__FILE__)}/../lib"

require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'sinatra/partial'
require 'sinatra/flash'
require 'json'
require 'yaml'
require 'net/http'
require 'sequel'
require 'better_errors'
require 'haml'

require_relative '../etc/toolenv'
require_relative '../lib/core'
require_relative '../lib/listhelper'
require_relative '../lib/playlist'

require_relative '../../hacauto/bin/hac-nhac'

set :bind,            '0.0.0.0'
set :lock,            true
set :show_exceptions, true
set :server,          'thin'
set :root,            "#{File.dirname(__FILE__)}/.."
set :haml,            {escape_html: false}

enable :sessions

# configure :development do
# use BetterErrors::Middleware
# BetterErrors.application_root = __dir__
# end

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# routes...
options '*' do
  response.headers['Allow'] = 'GET, POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token'
  response.headers['Access-Control-Allow-Origin'] = '*'
  200
end

get '/fragment_upload/:user_name/:song_id/:song_name' do |_user_name, _song_id, _song_name|
  locals = params.dup
  haml :fragment_upload, locals:
end

post '/song-style' do
  # Plog.dump_info(params:params)
  user      = params[:user]
  song_id   = params[:song_id]
  song_name = params[:song_name]
  pnote     = PlayNote.new(user)
  uperf_info = {
    instrument: params[:instrument], key: params[:key],
    intro: params[:intro],
    ytvideo: params[:ytvideo],   vidkey: params[:vidkey],
    ytkvideo: params[:ytkvideo], ytkkey: params[:ytkkey],
    smkey: params[:smkey],       smule: params[:smule],
    nctkey: params[:nctkey],     nct: params[:nct]
  }
  pnote.replace(song_id, song_name, uperf_info)
  flash[:notice] = "Style for #{song_name} replaced"
  redirect "/song-style/#{user}/#{song_id}/#{song_name}"
end

get '/song-style/:user/:song_id/:song_name' do |user, song_id, song_name|
  uperf_info = PlayNote.new(user)[song_name] || {}
  song_id    = song_id.to_i
  song_info  = SongInfo.new(song_id).content
  locals     = {user:, song_id:, song_name:,
                uperf_info:, song_info:}
  haml :song_style, locals:
end

get '/play-here' do
  ofile = params[:ofile]
  Plog.dump_info(ofile:)
  system("open -g \"#{ofile}\"") if test('f', ofile)
end

get '/playorder/:user/:listno' do |user, listno|
  playlists  = PlayList.for_user(user)
  list_info  = playlists.find { |r| r[:id] == listno.to_i }
  play_order = PlayOrder.new(listno)
  # Plog.dump_info(playlists:playlists, list_info:list_info)
  if params[:reset]
    play_order.create_file
  elsif params[:refresh]
    play_order.refresh_file
  end
  haml :playorder, locals: {play_order:, list_info:}
end

post '/playorder' do
  # Plog.dump_info(params:params)
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
  Plog.dump_info(singer:, params:)
  if params[:listno] && !params[:listno].empty? && params[:listno] != singer
    Plog.info('Redirecting')
    redirect "/singer_list/#{params[:listno]}"
  end
  reload       = params[:reload].to_i
  locals       = PlayList.collect_for_singer(singer, reload: reload == 2)
  singer_lists = PlayList.band_singers.map { |r| {name: r} }
  locals.update(user: 'thienv', playlists: nil, singer_lists:,
                note: nil)
  haml :perflist, locals:
end

get '/perflist/:user' do |user|
  Plog.dump_info(params:)
  reload   = params[:reload].to_i
  locals   = PlayList.collect_for_user(user, listno: params[:listno],
                                       reload: reload == 2)
  listno   = locals[:listno]
  notefile = "data/#{listno}.notes"
  note     = nil
  note = markdown(File.read(notefile)) if test('f', notefile)
  locals.update(user:, note:)
  haml :perflist, locals:
end

get '/send_patch/:pstring' do |pstring|
  command = "bk50set.rb apply_midi #{pstring}"
  unless (key = params[:key]).nil? || key.empty?
    command += " --key #{key}"
  end
  Plog.info(command)
  presult = JSON.parse(`#{command}`)
  haml :patch_info, locals: {presult:}, layout: nil
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
  singers   = {}
  smcontent = SmContent.new(user)
  records   = smcontent.content
  if !(days = params[:days]).nil? && ((days = days.to_i) > 0)
    records = records.where(created: Time.now - days * 24 * 3600..Time.now)
  end
  records.each do |r|
    record_by = r[:record_by].split(',')
    isfav     = r[:isfav] || r[:oldfav]
    content << r
    record_by.each do |asinger|
      siinfo = singers[asinger] ||= {name: asinger, count: 0, listens: 0,
                                     loves: 0, favs: 0}
      siinfo[:count]   += 1
      siinfo[:favs]    += 1 if isfav
      siinfo[:listens] += (r[:listens] || 0)
      siinfo[:loves]   += r[:loves].to_i
    end
  end
  # Front end will also do sort, but we do on backend so content would
  # not change during initial display
  singers = singers.values.sort_by { |r| r[:count] }.reverse
  Plog.dump_info(all_singers: smcontent.singers.count)
  haml :smulelist, locals: {user:, singers:,
                            all_singers: smcontent.singers,
                            join_me: smcontent.join_me,
                            i_join: smcontent.i_join}
end

get '/smulelist-perf/:user' do |user|
  # Plog.dump_info(params:params, _ofmt:'Y')
  start     = params[:start].to_i
  length    = (params[:length] || 10_000).to_i
  order     = (params[:order] || {}).values.first || {'column' => 5, 'dir' => 'desc'}
  days      = params[:days].to_i
  smcontent = SmContent.new(user)

  columns = %i[title isfav record_by listens loves created]
  records = smcontent.content
  records = records.left_join(smcontent.songinfos, song_info_url: :song_info_url)
  records = get_searches(records)
  records = records.where(created: Time.now - days * 24 * 3600..Time.now) if days > 0

  data0     = records
  ocolumn   = order['column'].to_i
  data0 = if order['dir'] == 'desc'
            data0.reverse(columns[ocolumn])
          else
            data0.order(columns[ocolumn])
          end
  # Plog.dump_info(search:search)

  data = data0.limit(length).offset(start)
  p data

  # Plog.dump_info(data:data.sql, data0:data0.sql)
  locals = {
    total:    records.count,
    filtered: data0.count,
    user:,
    data:,
  }
  yaml_src = erb(File.read('views/smule_data.yml'), locals:)
  data = YAML.safe_load(yaml_src)
  data['data'] ||= []
  data.to_json
end

get '/player/:sid' do |sid|
  ofile = '../hacauto/toplay.dat'
  File.open(ofile, 'a') do |fod|
    fod.puts sid
  end
end

get '/smulegroup2/:user' do |user|
  haml :smulegroup2, locals: {user:}
end

get '/smgroups_data/:user' do |user|
  # Plog.dump_info(params: params)
  Plog.dump_info(order: params[:order])
  start     = params[:start].to_i
  length    = (params[:length] || 1).to_i
  order     = (params[:order] || {}).values.first || {'column' => 2, 'dir' => 'desc'}
  # search    = (params[:search] || {})['value']

  smcontent = SmContent.new(user)
  columns   = %i[stitle record_by created tags listens loves]
  records   = smcontent.content.left_join(smcontent.songinfos, song_info_url: :song_info_url)

  data0     = records
  data0     = get_searches(data0)
  ocolumn   = order['column'].to_i
  odir      = order['dir']
  fmap      = %w[stitle record_by created tags]
  data0     = data0.group(:stitle)
  Plog.dump_info(query: data0, count: data0.count)
  total     = data0.count

  filtered  = data0.count

  Plog.dump_info(query: data0, count: data0.count)
  data0 = if odir == 'desc'
            data0.reverse(fmap[ocolumn])
          else
            data0.order(fmap[ocolumn])
          end
  stitles = data0.group(:stitle).map { |r| r[:stitle] }
  data0   = data0.limit(length).offset(start)
  Plog.dump_info(query: data0, count: data0.count)

  # data = records.where(stitle: stitles).reverse(:created)
  data = records.where(stitle: stitles[start..start + length - 1])
  data = if odir == 'desc'
           data.reverse(fmap[ocolumn])
         else
           data.order(fmap[ocolumn])
         end
  Plog.dump_info(query: data, count: data.count)
  data = data.map { |r| r }.group_by { |r| r[:stitle] }
             .reject do |_stitle, sinfos|
    sinfos.find { |sinfo| sinfo[:record_by] == user }
  end

  ndata = {}
  data.each do |stitle, slist|
    ndata[stitle] = {
      listens:   slist.inject(0) { |sum, x| sum + x[:listens] },
      loves:     slist.inject(0) { |sum, x| sum + x[:loves] },
      tags:      slist.inject([]) { |sum, x| sum << x[:tags] }
                      .join(',').split(',').uniq.join(', '),
      created:   slist[0][:created],
      stitle:    slist[0][:stitle],
      record_by: slist[0][:record_by],
      list:      slist,
    }
  end
  ndata = ndata.to_a.sort_by { |r| r[1][columns[ocolumn]] }
  ndata = ndata.reverse if order['dir'] == 'desc'

  locals = {
    total:,
    filtered:,
    user:,
    data:     ndata,
    all_singers: smcontent.singers,
  }
  yaml_src = erb(File.read('views/smgroups_data.yml'), locals:)
  YAML.safe_load(yaml_src).to_json
end

get '/smulegroup/:user' do |user|
  content   = []
  singer    = (params[:singer] || '').split
  tags      = (params[:tags] || '').split.join('|')
  tags      = tags.empty? ? nil : Regexp.new(tags)
  smcontent = SmContent.new(user)
  records   = smcontent.content.left_join(smcontent.songinfos, song_info_url: :song_info_url)
                       .reverse(:created)
  records.each do |r|
    unless singer.empty?
      record_by = r[:record_by].split(',')
      next if (record_by & singer).empty?
    end
    next if params[:title] && r[:title] != params[:title]

    next if tags && r[:tags] !~ tags

    content << r
  end
  scontent = content.group_by { |r| r[:title].downcase.sub(/\s*\(.*$/, '') }
  haml :smulegroup, locals: {user:, scontent:,
                             all_singers: smcontent.singers}
end

get '/dl-transpose/:video' do |video|
  offset = params[:offset].to_i
  download_transpose(video, offset, params)
end

get '/reload-song/:song_id' do |song_id|
  files = Dir.glob("data/SONGS/song:#{song_id}:*")
  Plog.dump_info(files:)
  FileUtils.rm(files, verbose: true)
end

KEY_POS = %w[A A#|Bb B C C#|Db D D#|Eb E F F#|Gb G G#|Ab].freeze
helpers do
  def download_transpose(video, offset, options)
    require 'tempfile'

    Plog.dump_info(options:)
    url   = "https://www.youtube.com/watch?v=#{video}"
    odir  = options[:odir]  || 'data/MP3'
    ofile = options[:title] || '%(title)s-%(creator)s-%(release_date)s'
    key   = params[:key] || offset
    ofile = "#{odir}/#{ofile}=#{video}=#{key}"
    if test('s', "#{ofile}.mp3")
      Plog.info("#{ofile}.mp3 already exist.  Skip download")
      return
    end
    ofmt = "#{ofile}-pre.%(ext)s"
    command = 'youtube-dl --extract-audio --audio-format mp3 --audio-quality 0 --embed-thumbnail'
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

  # Attach play note to the like star
  def key_offset(base_key, new_key, closer: false)
    if !base_key || !new_key || base_key.empty? || new_key.empty?
      Plog.dump_info(msg: 'No key', base_key:, new_key:)
      return 0
    end
    base_key = base_key.sub(/m$/, '')
    new_key  = new_key.sub(/m$/, '')
    # Plog.info({base_key:base_key, new_key:new_key}.inspect)
    new_offset = KEY_POS.index { |f| new_key =~ /^#{f}$/ }
    base_offset = KEY_POS.index { |f| base_key =~ /^#{f}$/ }
    if !new_offset || !base_offset
      Plog.dump_info(msg: 'No key offset', base_key:, new_key:) if new_key && !new_key.empty?
      return 0
    end
    offset = new_offset - base_offset
    offset += 12 if offset < 0
    # Keep offfset close for vis
    offset -= 12 if closer && (offset >= 6)
    offset
  end

  # For flashcard - memorize.
  def clean_and_split(lyric, position)
    result = []
    lyric.gsub(/\s*\r/, '').gsub(/^---/, '<hr/>').split("\n").each do |l|
      words = l.gsub(%r{<span.*?</span>}, '').split
               .map { |w| w.sub(/\([^)]*\)/, '') }
               .reject(&:empty?)
      position += 1 if words[0].include?(':')
      span1 = words[0..position - 1].join(' ').to_s
      span2 = (words[position..] || []).join(' ').to_s
      result << [span1, span2]
    end
    result
  end

  def get_searches(records)
    searches = if params[:search_c] && !params[:search_c].empty?
                 [params[:search_c]]
               else
                 (params[:search] || {})['value'].split(',')
               end

    dsearches = []
    searches.each do |search|
      next if search.empty?

      case search
      when /^f:/
        records = records.filter(isfav: true).or(oldfav: true)
      when /^o:/
        records = records.where(Sequel.lit("href like '%ensembles'"))
      when /^t:/
        dsearches << [%w[tags author singer], Regexp.last_match.post_match]
      when /^s:/
        dsearches << [%w[sfile], Regexp.last_match.post_match]
      when /^r:/
        dsearches << [%w[record_by], Regexp.last_match.post_match]
      when /^c:/
        dsearches << [%w[orig_city other_city], Regexp.last_match.post_match]
      else
        dsearches << [%w[performances.stitle record_by], search]
      end
    end
    # Plog.dump_info(searches:searches, dsearches:dsearches)

    dsearches.each do |sfields, search|
      search = search.downcase.gsub(/_/, '/_')
      pdata   = []
      query   = sfields.map do |f|
        pdata << "%#{search}%"
        "LOWER(#{f}) like ? escape '/'"
      end.join(' or ')
      records = records.where(Sequel.lit(query, *pdata))
    end
    Plog.dump_info(records:, count: records.count)
    records
  end
end

def search_data_file(fname)
  ["#{ENV['HOME']}/shared/#{fname}",
   "/Volumes/Voice/SMULE/#{fname}"].each do |afile|
    # Plog.dump_info(afile:afile, fname:fname)
    return afile if test('r', afile)
  end
  nil
end

# DB Cache Definition
class DBCache
  class << self
    DBNAME = 'smule.db'

    def dbase
      @dbase ||= Sequel.sqlite(DBNAME)
    end
  end
end

# SM Content Definition
class SmContent
  attr_reader :join_me, :i_join

  def content
    DBCache.dbase[:performances]
           .where(deleted: nil).or(deleted: 0)
           .where(Sequel.lit("record_by like '%#{@user}%'"))
  end

  def singers
    DBCache.dbase[:singers]
  end

  def songinfos
    DBCache.dbase[:song_infos]
  end

  def initialize(user)
    @user    = user
    @join_me = {}
    @i_join  = {}

    DBCache.dbase
    content.where(Sequel.lit("record_by like '%#{user}%'"))
           .each do |r|
      rby = r[:record_by].split(',')
      if rby[0] == user
        other = rby[1]
        @join_me[other] ||= 0
        @join_me[other] += 1
      end
      next unless rby[1] == user

      other = rby[0]
      @i_join[other] ||= 0
      @i_join[other] += 1
    end
  end

  def remove(sid)
    Plog.info("Deleting #{sid}")
    content.where(sid:).delete
    true
  end
end

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

# Extract video info (youtube)
class VideoInfo
  attr_reader :videos, :yk_videos

  def initialize(vstring, kstring=nil)
    yvideos = (vstring || '').split('|')
    vidkeys = (kstring || '').split('|')
    @yk_videos = yvideos.zip(vidkeys)
    check_videos
  end

  # Select set is "1/2/3"
  # If there is one or more solo index specified.  Use it since same song
  # could be played in multiple styles
  def select_set(solo_idx)
    if solo_idx && !@yk_videos.empty?
      solo_sel   = solo_idx.split('/').map(&:to_i)
      @yk_videos = @yk_videos.values_at(*solo_sel).compact
      # Plog.dump_info(solo_sel:solo_sel, yk_videos:@yk_videos)
      check_videos
    end
    @yk_videos
  end

  def check_videos
    @videos = []
    @yk_videos.each do |svideo, key|
      video, *ytoffset = svideo.split(',')
      ytoffset.each_slice(2) do |ytstart, ytend|
        ytstart = Regexp.last_match.pre_match.to_i * 60 + Regexp.last_match.post_match if ytstart =~ /:/
        ytend   = Regexp.last_match.pre_match.to_i * 60 + Regexp.last_match.post_match if ytend =~ /:/
        vid = "video_#{video.gsub(/[^a-z0-9_]/i, '')}_#{ytstart}_#{ytend}"
        # Plog.dump_info(vid:vid)
        @videos << {
          vid:, video:, key:,
          start: ytstart.to_i, end: ytend.to_i
        }
      end
    end
  end
end
