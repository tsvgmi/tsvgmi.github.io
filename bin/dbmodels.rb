#!/usr/bin/env ruby
# frozen_string_literal: true

#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require_relative '../etc/toolenv'
require 'sequel'
require 'yaml'
require 'core'

# Sequel::Model.db = Sequel.connect('mysql2://playlist:playlistpasswd@127.0.0.1/Playlist')
module DbUtils
  def create_or_update(keys, values)
    if (dbrec = first(keys)).empty?
      vset = keys
      vset.update(values)
      Plog.dump_info(vset:)
      dbrec = create(vset)
    else
      # Don't update nil value
      values.each do |vk, vv|
        values.delete(vk) unless vv
      end
      dbrec.update(values)
      dbrec.save
    end
    dbrec
  end
end

# Song Definitions
class Song < Sequel::Model
  extend DbUtils
end

# Song Definitions
class Singer < Sequel::Model
  extend DbUtils
end

# Sound Definitions
class Sound < Sequel::Model
  extend DbUtils
end

# Dbm Definitions
class Dbm
  extend_cli __FILE__

  class << self
    def load_order_to_db(order_file)
      YAML.load_file(order_file).each do |agroup|
        agroup['list'].each do |entry|
          name_k, singer, key = entry.split(',')
          keys   = {name_k:, singer:}
          values = {key:}
          Singer.create_or_update(keys, values)
        end
      end
    end

    def load_to_db(slist_file)
      Singer.strict_param_setting = false
      YAML.load_file(slist_file).each do |se|
        name_k = se[:name_k]
        name_k ||= (se[:href] || '').split('/')[5]
        p name_k, se
        next unless name_k

        keys   = {name_k:}
        values = {
          name:      se[:name],
          artist:    se[:artist],
          key:       se[:play_key],
          lyric_url: se[:href],
          play_url:  se[:play_link],
          preview:   se[:preview],
          style:     se[:pstyle],
          perfnote:  se[:perfnote],
        }
        Song.create_or_update(keys, values)
        if se[:perform]
          se[:perform].each do |aperf|
            keys = {
              name_k:,
              singer: aperf[:singer],
            }
            values = {
              key:       aperf[:key]   || se[:play_key],
              style:     aperf[:style] || se[:pstyle],
              transpose: (se[:skey] || 0).to_i,
            }
            Singer.create_or_update(keys, values)
          end
        elsif se[:performer]
          keys = {
            name_k:,
            singer: se[:performer],
          }
          values = {
            key:       se[:play_key],
            style:     se[:pstyle],
            transpose: (se[:skey] || 0).to_i,
          }
          Singer.create_or_update(keys, values)
        end
        next unless se[:sound]

        keys   = {name_k:}
        values = {bk3_set: se[:sound]}
        Sound.create_or_update(keys, values)
      end
      true
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Dbm.handle_cli(
    ['--auth',         '-a', 1],
    ['--check_lyrics', '-k', 0],
    ['--limit',        '-l', 1],
    ['--ofile',        '-o', 1],
    ['--exclude_user', '-x', 1]
  )
end
