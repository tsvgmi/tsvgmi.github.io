#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "#{File.dirname(__FILE__)}/../lib"

require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/partial'
require 'sinatra/flash'

require 'json'
require 'yaml'
require 'net/http'
require 'sequel'
require 'haml'

require_relative '../etc/toolenv'
require_relative '../lib/core'

require 'db_cache'
require 'sm_content'
require 'plog'
require 'play_list'

set :bind,            '0.0.0.0'
set :port,            (ENV['PORT'] || 4568).to_i
set :lock,            true
set :show_exceptions, true
set :server,          'thin'
set :root,            "#{File.dirname(__FILE__)}/.."
set :haml,            {escape_html: false}

enable :sessions

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
end

