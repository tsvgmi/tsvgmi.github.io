#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/etc/toolenv"
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'sinatra/partial'
require 'yaml'
require 'net/http'
require 'core'

#set :bind, '0.0.0.0'

get '/' do
  redirect "/program/vnhv-thu-2017"
end

get '/list/:event' do |event|
  haml :list, locals: {event: event}, layout:nil
end

get '/program/:event' do |event|
  ord_list   = YAML.load_file("#{event}.order")
  song_store = load_songs(event)
  performers = []
  styles     = []
  ord_list.each_with_index do |asection, sec_no|
    asection['list'].each do |aname|
      sentry = song_store[aname]
      next unless sentry
      if sentry[:performer]
        performers += sentry[:performer].split(/\s*,\s*/)
      end
      if sentry[:pstyle]
        styles << sentry[:pstyle].downcase
      end
    end
  end
  performers = performers.sort.uniq
  styles     = styles.sort.uniq
  haml :program, locals: {ord_list:ord_list, song_store:song_store,
                          performers:performers, styles:styles}
end

get '/knockout/:event' do |event|
  ord_list   = YAML.load_file("#{event}.order")
  song_store = load_songs(event)
  haml :knockout, locals: {ord_list:ord_list, song_store:song_store}
end

get '/send_patch/:pstring' do |pstring|
  command = "bk50set.rb apply_midi #{pstring}"
  presult = JSON.parse(`#{command}`)
  haml :patch_info, locals: {presult:presult}, layout:nil
end

get '/show_lyric' do
  url   = params[:url]
  #lfile = "data/" + url.gsub('/', '#')
  #unless test(?s, lfile)
  #content = Net::HTTP.get(URI.parse(url))
  lyric_info(url).to_json
end

helpers do
  def load_songs(event)
    plist = YAML.load_file("#{event}.slist").each do |e|
      e[:sname] = e[:href] ? e[:href].split('/')[5] : e[:name].downcase
            end
    Hash[plist.map{|e| [e[:sname], e]}]
  end

  def lyric_info(url)
    Plog.info("Extract lyrics from #{url}")
    lfile = "data/#{url.sub(/\/$/, '').gsub('/', '#')}"
    if test(?s, lfile)
      return YAML.load_file(lfile)
    else
      page   = get_page(url)
    end
    lyric  = page.css('.chord_lyric_line').map{|r| r.text.strip}.join("\n").
              strip.gsub(/ \]/, ']')
    artist = page.css('.perform-singer-list').map {|r| r.text.strip}
    ret = {
      title:  page.css('#song-title').text.strip,
      artist: artist.join(', '),
      lyric:  lyric,
    }
    File.open(lfile, "w") do |fod|
      fod.puts ret.to_yaml
    end
    ret
  end

  def get_page(url)
    require 'open-uri'
    require 'nokogiri'

    fid  = open(url)
    page = Nokogiri::HTML(fid.read)
    fid.close
    page
  end

end
