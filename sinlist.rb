#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/etc/toolenv"
require 'sinatra'
require 'sinatra/content_for'
require 'yaml'
require 'core'

#set :bind, '0.0.0.0'

get '/' do
  haml :index
end

get '/list/:event' do |event|
  haml :list, locals: {event: event}, layout:nil
end

get '/content/:event' do |event|
  plist = load_plist(event)
  haml :content, locals: {plist:plist}
end

get '/program/:event' do |event|
  plist = load_plist(event)
  haml :program, locals: {plist:plist}
end

get '/master/:event' do |event|
  ord_list   = YAML.load_file("#{event}.order2")
  song_store = load_songs(event)
  haml :master, locals: {ord_list:ord_list, song_store:song_store}
end

get '/send_patch/:pstring' do |pstring|
  command = "bk50set.rb apply_midi #{pstring}"
  presult = JSON.parse(`#{command}`)
  haml :patch_info, locals: {presult:presult}, layout:nil
end

helpers do
  def load_plist(event)
    p2list = load_songs(event)
    order_list = File.read("#{event}.order").split("\n")
    order_list.map{|e| [e, p2list[e]]}
  end

  def load_songs(event)
    plist = YAML.load_file("#{event}.slist").each do |e|
      e[:sname] = e[:href] ? e[:href].split('/')[5] : e[:name].downcase
            end
    Hash[plist.map{|e| [e[:sname], e]}]
  end
end
