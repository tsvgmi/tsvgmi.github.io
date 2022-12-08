#!/usr/bin/env ruby
# frozen_string_literal: true

#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require "#{File.dirname(__FILE__)}/../etc/toolenv"
$LOAD_PATH << File.dirname(__FILE__)
require 'json'
require 'yaml'
require 'core'

# Playlist handling
class PlayList
  extend_cli __FILE__

  HAC_URL = 'https://hopamchuan.com'

  def initialize(list_info)
    if list_info.is_a?(Hash)
      listno = list_info[:id]
      @save_list = list_info.clone
    else
      listno = list_info
      @save_list = {id: listno}
    end
    @list_id = listno
  end

  def fetch(new: false)
    cfile = "data/list_content-#{@list_id}.yml"
    if !new && test('s', cfile)
      @save_list = YAML.load_file(cfile)
    else
      @save_list[:content] = HacSource.new.playlist("#{HAC_URL}/playlist/v/#{@list_id}")
      File.open(cfile, 'w') do |fod|
        fod.puts @save_list.to_yaml
      end
      @save_list
    end
    @save_list
  end

  class << self
    def band_singers
      %w[bich-hien gia-cau mai-huong michelle mike thanh
         thanh-liem thien thien-huong thuy-dung yen-phuong]
    end

    def collect_for_user(user, listno: nil, reload: false, options: {})
      reload = reload == 'true' if reload.is_a?(String)

      playlists = PlayList.for_user(user, reload:)
      raise "No playlists found for user #{user}" if playlists.size <= 0

      listno ||= playlists[0][:id]

      list_info  = playlists.find { |r| r[:id].to_i == listno.to_i }
      play_order = PlayOrder.new(listno, options)
      order_list = Hash[play_order.content_str]
      song_list  = play_order.fetch_songs
      {
        listno:,
        list_info:,
        playlists:,
        order_list:,
        song_list:,
        singers:    play_order.singers,
        leads:      play_order.leads,
        perf_info:  PlayNote.new(user),
      }
    end

    def for_user(user, reload: false)
      cfile = "data/list_for_user-#{user}.yml"
      if !reload && test('s', cfile)
        ulist = YAML.load_file(cfile)
      else
        ulist = HacSource.new.list_for_user("#{HAC_URL}/profile/playlists/#{user}")
        File.open(cfile, 'w') do |fod|
          fod.puts ulist.to_yaml
        end
        ulist
      end
    end

    def collect_for_singer(singer, reload: false)
      playlists  = PlayList.for_singer(singer, reload:)
      play_order = PlayOrder.new(singer)
      order_list = Hash[play_order.content_str]
      song_list  = play_order.fetch_songs
      {
        list_no:    singer,
        list_info:  playlists[0],
        playlists:,
        order_list:,
        song_list:,
        singers:    play_order.singers,
        leads:      play_order.leads,
        perf_info:  PlayNote.new('thienv'),
      }
    end

    def for_singer(singer, reload: false)
      gen_singer_list(singer, reload:)
      [
        {
          id:         singer,
          href:       "file:///#{Dir.pwd}/data/list_content-#{singer}.yml",
          name:       "List for #{singer}",
          song_count: 1,
        }
      ]
    end

    def gen_singer_list(singer, reload: false)
      order_file = "#{Dir.pwd}/data/#{singer}.order"
      Plog.dump_info(reload:, order_file:)
      if !reload && test('f', order_file)
        Plog.dump_info(reload:, nreload: !reload, order_file:)
        return true
      end
      sids = {}
      scontent = []
      `cat data/*.order | fgrep ",#{singer}," | sort -u`.split("\n").each do |l|
        fs = l.split(/,/)
        rsinger = fs[3]
        next unless singer == rsinger

        sid = fs[0].to_i.abs
        sids[sid] = true
        scontent << l
      end
      raise "No song found for #{singer}" unless sids.empty?

      Plog.info("Collect #{sids.size} songs for #{singer}")

      ssinfo = {}
      Dir.glob('data/list_content-*.yml').each do |afile|
        next unless afile =~ /list_content-\d+.yml$/

        Plog.info("Loading #{afile}")
        YAML.load_file(afile)[:content].each do |sinfo|
          # Plog.dump_info(sinfo:sinfo)
          ssinfo[sinfo[:song_id]] = sinfo if sids[sinfo[:song_id]]
        end
      end

      lcontent_file = "data/list_content-#{singer}.yml"
      File.open(lcontent_file, 'w') do |fod|
        fod.puts({
          id:      singer,
          content: ssinfo.values,
        }.to_yaml)
      end

      File.open(order_file, 'w') do |fod|
        fod.puts scontent.join("\n")
      end
      true
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  PlayList.handle_cli(
    ['--channel', '-C', 1],
    ['--key',     '-k', 1]
  )
end
