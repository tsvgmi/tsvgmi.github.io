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
require Dir.pwd + '/bin/dbmodels'

set :bind, '0.0.0.0'

get '/' do
  redirect "/program/vnhv-thu-2017"
end

get '/list/:event' do |event|
  haml :list, locals: {event: event}, layout:nil
end

get '/program/:event' do |event|
  ord_list   = YAML.load_file("#{event}.order")
  song_store = load_songs(ord_list)
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
  def load_songs(ord_list)
    songs = []
    ord_list.each do |lpart|
      songs    += (lpart['list'] || []).map{|se| se.split(',')[0]}
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
      path = (sentry[:lyric_url] || '').split('/')
      if path.size >= 7
        sno, song, user = path[-3], path[-2], path[-1]
        sfile = "/Users/tvuong/myprofile/#{user}/#{sno}::#{sname}.yml"
        if test(?s, sfile)
          flat = sentry[:kofs] =~ /f$/
          kofs = sentry[:kofs].to_i
          Plog.info "Transposing #{sfile}"
          sentry[:lyric] = ListHelper.transpose_song(sfile, kofs, flat:flat)
        else
          Plog.error("#{sfile} not found - source: #{sentry[:lyric_url]}")
        end
      end
    end
    song_list
  end
end
