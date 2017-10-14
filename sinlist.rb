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

get '/send_patch/:pstring' do |pstring|
  command = "bk50set.rb apply_midi #{pstring}"
  presult = JSON.parse(`#{command}`)
  haml :patch_info, locals: {presult:presult}, layout:nil
end

helpers do
  def load_plist(event)
    plist = YAML.load_file("#{event}.slist").each do |e|
      e[:sname] = e[:href] ? e[:href].split('/')[5] : e[:name].downcase
            end
    ord_file   = "#{event}.order"
    order_list = if test(?s, ord_file)
      File.read(ord_file).split("\n")
    else
      plist.map{|r| r[:sname]}.sort
    end
    p2list = Hash[plist.map{|e| [e[:sname], e]}]
    Plog.dump_info(p2list:p2list)
    order_list.map{|e| [e, p2list[e]]}
  end
end
