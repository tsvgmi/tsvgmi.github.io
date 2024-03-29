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
require 'nokogiri'
require 'yaml'
require 'cgi'
require 'core'


# Handling of list
class ListHelper
  extend_cli __FILE__

  class << self
    def youtube_dl(url, ofile=nil)
      return false if ofile && test('s', ofile)

      command = 'youtube-dl --extract-audio --audio-format mp3'
      command += " -o '#{ofile}.%(ext)s'" if ofile
      system "#{command} '#{url}'"
      exec "bin/sliceit #{ofile}.mp3 0 180" if ofile
      true
    end

    def download_youtube_files(sl_file)
      slist = SongStore.new(sl_file)
      slist = slist.songs.select do |e|
        e[:play_link] && e[:href] && e[:play_link] =~ /youtube/
      end
      slist.each do |e|
        sname = e[:href].split('/')[5]
        ofile = "audio/#{sname}.mp3"
        Plog.info "Downloading for #{e[:name]}" if youtube_dl(e[:play_link], ofile)
      end
      true
    end

    def load_plist(event)
      plist = YAML.load_file("#{event}.slist").each do |e|
        e[:sname] = e[:href] ? e[:href].split('/')[5] : e[:name]
      end
      ord_file   = "#{event}.order"
      order_list = nil
      if test('s', ord_file)
        order_list = File.read(ord_file).split("\n")
        Plog.dump_info(ord_file:, order_list:)
      else
        order_list = plist.map { |r| r[:sname] }
      end
      p2list = Hash[plist.map { |e| [e[:sname], e] }]
      order_list.map { |e| p2list[e] }
    end

    def create_db
      require 'sequel'

      Sequel.connect('mysql://playlist:play123@localhost/Playlist')
    end

    def load_to_db(slist_file)
      require 'sequel'

      dbase = Sequel.connect('mysql://playlist:play123@localhost/Playlist')
      YAML.load_file(slist_file).each do |_se|
        dbase[:songs].insert(record)
      end
    end

    # 12 elemement list of key and alternate notation.  Use '|'
    # between alternate notation so it could be matched with regexp
    KEY_POS = %w[A A#|Bb B C C#|Db D D#|Eb E F F#|Gb G G#|Ab].freeze
    def transpose_mkey(keys, offset, options={})
      output = []
      # Incase key is specified as chord/bass.  We transpose both
      keys.split('/').each do |key|
        # Extract base key and mod (sharp/flat)
        if key[1] =~ /[#b]/
          bkey = key[0..1]
          mod  = key[2..].strip
        else
          bkey = key[0]
          mod  = key[1..].strip
        end
        # Order of key (0-11)
        bofs = KEY_POS.index { |k| bkey =~ /^#{k}$/ }
        if bofs
          # Calculate target key
          tkey  = KEY_POS[(bofs + offset + 12) % 12]
          # Select alternate notations (sharp or flat)
          tkeys = tkey.split('|')
          output << if options[:flat]
                      tkeys[-1] + mod
                    else
                      tkeys[0] + mod
                    end
        else
          Plog.error("Does not know how to transpose #{key}")
          output << key
        end
      end
      output.compact.join('/')
    end

    # List of base keys using flat notation
    FLAT_KEYS = %w[Dm F Bbm Db Cm Eb Ebm Gb Fm Ab Gm Bb].freeze
    # Transpose a lyric stream for # of offset semitones
    def transpose_lyric(lyric, offset, options={})
      # Target key.  Need to know since this control whethere
      # to use flat or sharp
      to_basechord = if options[:fromkey]
                       target_chord(options[:fromkey], offset)
                     else
                       options[:tokey]
                     end

      # Special rule.  If target key uses flat notation, all mod should use flat
      options[:flat] = to_basechord && FLAT_KEYS.include?(to_basechord)
      offset         = offset.to_i
      output         = ''
      cclass         = options[:cclass] || 'chord'
      tclass         = options[:tclass] || 'none'
      # Plog.dump_info(offset:offset, options:options)
      # Pick out the chords notation, transpose anre replace it back
      lyric.scan(/([^\[]*)\[([^\]]+)\]/m).each do |text, chord|
        tchord = transpose_mkey(chord, offset, options)
        # Adding span only for my usecase for now.
        output += "<span class='#{tclass}'>#{text}</span><span class=\"#{cclass}\">#{tchord}</span>"
      end
      last_span = lyric.sub(/^.*\]/m, '')
      output += "<span class='#{tclass}'>#{last_span}</span>"
      output.gsub(/\|/, "<span class='#{cclass}'>|</span>")
    end

    MAJOR_CHORDS = %w[A Bb B C Db D Eb E F F# G Ab].freeze
    MINOR_CHORDS = %w[Am Bbm Bm Cm Dbm Dm Ebm Em Fm Gbm Gm Abm].freeze
    def target_chord(base_chord, offset)
      if !(coffset = MAJOR_CHORDS.index(base_chord)).nil?
        MAJOR_CHORDS[(coffset + offset) % 12]
      elsif !(coffset = MINOR_CHORDS.index(base_chord)).nil?
        MINOR_CHORDS[(coffset + offset) % 12]
      else
        Plog.error("Unknown chord to locate target: #{base_chord}")
        base_chord
      end
    end

    def transpose_song(sfile, offset, options={})
      offset   = offset.to_i
      cur_song = YAML.load_file(sfile)
      cur_song[:lyric] = transpose_lyric(cur_song[:lyric], offset, options)
      cur_song
    end

    def _replace_with_local_lyric(href)
      hrefs = href.split('/')

      if hrefs.size == 6
        sno   = hrefs[4]
        sname = hrefs[5]
        # suser = hrefs[6]
        # Replace with my version
        lfiles = Dir.glob("/Users/tvuong/myprofile/*/#{sno}::#{sname}.yml")
        unless lfiles.empty?
          luser = lfiles[0].split('/')[4]
          href  = href.sub(%r{/$}, '') + "/#{luser}"
        end
      end
      [sname, href]
    end

    def fill_slist(file)
      wset = {}
      Dir.glob('data/*.order').each do |afile|
        File.read(afile).split("\n").each do |aline|
          key, *values = aline.chomp.sub(/,+$/, '').split(',')
          # Plog.dump_info(afile:afile, key:key, values:values)
          next unless values.size >= 3

          wset[key] ||= []
          wset[key] << values
          # Plog.dump_info(afile:afile, key:key, values:values)
        end
      end
      handled = {}
      File.read(file).split("\n").each do |aline|
        key, *values = aline.chomp.sub(/,+$/, '').split(',')
        if handled[key] || !wset[key] || (values.size >= 3)
          puts aline
          next
        end
        handled[key] = true
        wset[key].uniq.each do |wvals|
          puts "#{key},#{wvals.join(',')}"
        end
      end
      true
    end

    def build_slist(url, list_name=nil)
      $LOAD_PATH << '/Users/tvuong/myprofile/bin'
      require '/Users/tvuong/bin/hacauto'

      list_name ||= File.basename(url)
      pl_songs = HacSource.playlist(url, get_option)
      sl_file  = "#{list_name}.slist"

      songs = {}
      if test('s', sl_file)
        YAML.load_file(sl_file).each do |asong|
          sname, asong[:href] = _replace_with_local_lyric(asong[:href])
          songs[sname] = asong
        end
      end
      pl_songs.each do |asong|
        sname, asong[:href] = _replace_with_local_lyric(asong[:href])
        songs[sname] ||= asong
      end
      Plog.info "Updating #{sl_file}"
      File.open(sl_file, 'w') do |fod|
        fod.puts songs.values.to_yaml
      end

      ord_file = "#{list_name}.order"
      if test('s', ord_file)
        cur_ord = YAML.load_file(ord_file)[0]
        cur_list = cur_ord['list'].map do |asong|
          asong.split(',')[0]
        end
        new_songs = songs.keys - cur_list
        Plog.info "Adding #{new_songs}"
        cur_ord['list'] += new_songs
      else
        cur_ord = {
          'name' => 'All',
          'list' => songs.keys,
        }
      end
      Plog.info "Updating #{ord_file}"
      File.open(ord_file, 'w') do |fod|
        fod.puts [cur_ord].to_yaml
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  ListHelper.handle_cli(
    ['--auth',         '-a', 1],
    ['--check_lyrics', '-k', 0],
    ['--flat',         '-F', 0],
    ['--limit',        '-l', 1],
    ['--ofile',        '-o', 1],
    ['--exclude_user', '-x', 1]
  )
end
