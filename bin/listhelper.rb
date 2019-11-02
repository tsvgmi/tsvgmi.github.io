#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require_relative "../etc/toolenv"
require 'nokogiri'
require 'yaml'
require 'cgi'
require 'core'

# Common functions
module HtmlRes
  def get_page(url)
    require 'open-uri'

    fid  = open(url)
    page = Nokogiri::HTML(fid.read)
    fid.close
    page
  end

end

class SongStore
  attr_reader :file, :songs

  def initialize(file, random=false)
    @file   = file
    @curptr = 0
    @songs  = []
    if test(?s, file)
      @songs = YAML.load_file(file)
      @songs = songs.sort_by{rand} if rand
      Plog.info "Reading #{@songs.size} entries from #{@file}"
    end
  end

  def save
    if @curptr < @songs.size
      csize = @songs.size - @curptr
      Plog.info "Writing remaining #{csize} entries to #{@file}"
      File.open(@file, "w") do |fod|
        fod.puts @songs[@curptr..-1].to_yaml
      end
    else
      Plog.info "Complete list from #{@file}.  Removing it"
      File.delete(@file)
    end
  end

  # Overwrite everything here
  def write(slist)
    @songs  = slist
    @curptr = 0
    save
  end

  def advance(offset=1)
    @curptr += offset
  end

  def peek
    @songs[@curptr]
  end
end

class ListHelper
  extendCli __FILE__

  class << self
    def youtube_dl(url, ofile=nil)
      if ofile && test(?s, ofile)
        return false
      end
      command = "youtube-dl --extract-audio --audio-format mp3"
      command += " -o '#{ofile}.%(ext)s'" if ofile
      system "#{command} '#{url}'"
      if ofile
        exec "bin/sliceit #{ofile}.mp3 0 180"
      end
      true
    end

    def download_youtube_files(sl_file)
      slist = SongStore.new(sl_file)
      slist.songs.select {|e|
        e[:play_link] && e[:href] && e[:play_link] =~ /youtube/
      }.each do |e|
        sname   = e[:href].split('/')[5]
        ofile = "audio/#{sname}.mp3"
        if youtube_dl(e[:play_link], ofile)
          Plog.info "Downloading for #{e[:name]}"
        end
      end
      true
    end

    def load_plist(event)
      plist = YAML.load_file("#{event}.slist").each do |e|
                e[:sname] = e[:href] ? e[:href].split('/')[5] : e[:name]
              end
      ord_file   = "#{event}.order"
      order_list = nil
      if test(?s, ord_file)
        order_list = File.read(ord_file).split("\n")
        Plog.dump_info(ord_file:ord_file, order_list:order_list)
      else
        order_list = plist.map{|r| r[:sname]}
      end
      p2list = Hash[plist.map{|e| [e[:sname], e]}]
      order_list.map{|e| p2list[e]}
    end

    def create_db
       require 'sequel'

       dbase = Sequel.connect('mysql://playlist:play123@localhost/Playlist')
    end

    def load_to_db(slist_file)
       require 'sequel'

       dbase = Sequel.connect('mysql://playlist:play123@localhost/Playlist')
       YAML.load_file(slist_file).each do |se|
         dbase[:songs].insert(record)
       end
    end

    # 12 elemement list of key and alternate notation.  Use '|'
    # between alternate notation so it could be matched with regexp
    KeyPos = %w(A A#|Bb B C C#|Db D D#|Eb E F F#|Gb G G#|Ab)
    def transpose_mkey(keys, offset, options={})
      output = []
      # Incase key is specified as chord/bass.  We transpose both
      keys.split('/').each do |key|
        # Extract base key and mod (sharp/flat)
        if key[1] =~ /[#b]/
          bkey = key[0..1]
          mod  = key[2..-1].strip
        else
          bkey = key[0]
          mod  = key[1..-1].strip
        end
        # Order of key (0-11)
        bofs = KeyPos.index{|k| bkey =~ /^#{k}$/}
        if bofs
          # Calculate target key
          tkey  = KeyPos[(bofs+offset+12) % 12]
          # Select alternate notations (sharp or flat)
          tkeys = tkey. split('|')
          if options[:flat]
            output << tkeys[-1]+mod
          else
            output << tkeys[0]+mod
          end
        else
          Plog.error("Does not know how to transpose #{key}")
          output << key
        end
      end
      output.compact.join('/')
    end

    # List of base keys using flat notation
    FlatKeys = %w(Dm F Bbm Db Cm Eb Ebm Gb Fm Ab Gm Bb)
    # Transpose a lyric stream for # of offset semitones
    def transpose_lyric(lyric, offset, options={})
      # Target key.  Need to know since this control whethere
      # to use flat or sharp
      to_basechord = options[:fromkey] ?
        target_chord(options[:fromkey], offset) :
        to_basechord = options[:tokey]

      # Special rule.  If target key uses flat notation, all mod should use flat
      options[:flat] = to_basechord && FlatKeys.include?(to_basechord)
      offset         = offset.to_i
      output         = ""
      cclass         = options[:cclass] || 'chord'
      tclass         = options[:tclass] || 'none'
      #Plog.dump_info(offset:offset, options:options)
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

    MajorChords = %w(A Bb B C Db D Eb E F F# G Ab)
    MinorChords = %w(Am Bbm Bm Cm Dbm Dm Ebm Em Fm Gbm Gm Abm)
    def target_chord(base_chord, offset)
      if coffset = MajorChords.index(base_chord)
        return MajorChords[(coffset + offset) % 12]
      elsif coffset = MinorChords.index(base_chord)
        return MinorChords[(coffset + offset) % 12]
      else
        Plog.error("Unknown chord to locate target: #{base_chord}")
        return base_chord
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
        sno, sname, suser = hrefs[4], hrefs[5], hrefs[6]
        # Replace with my version
        lfiles = Dir.glob("/Users/tvuong/myprofile/*/#{sno}::#{sname}.yml")
        if lfiles.size > 0
          luser = lfiles[0].split('/')[4]
          href  = href.sub(/\/$/, '') + "/#{luser}"
        end
      end
      [sname, href]
    end

    def fill_slist(file)
      wset = {}
      Dir.glob("data/*.order").each do |afile|
        File.read(afile).split("\n").each do |aline|
          key, *values = aline.chomp.sub(/,+$/, '').split(',')
          #Plog.dump_info(afile:afile, key:key, values:values)
          if values.size >= 3
            wset[key] ||= []
            wset[key] << values
            #Plog.dump_info(afile:afile, key:key, values:values)
          end
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
      $: << '/Users/tvuong/myprofile/bin'
      require '/Users/tvuong/bin/hacauto'

      list_name ||= File.basename(url)
      pl_songs = HacSource.playlist(url, getOption)
      sl_file  = "#{list_name}.slist"

      songs = {}
      if test(?s, sl_file)
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
      File.open(sl_file, "w") do |fod|
        fod.puts songs.values.to_yaml
      end

      ord_file = "#{list_name}.order"
      ord_list = []
      if test(?s, ord_file)
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
          'list' => songs.keys
        }
      end
      Plog.info "Updating #{ord_file}"
      File.open(ord_file, "w") do |fod|
        fod.puts [cur_ord].to_yaml
      end
    end
  end
end

if (__FILE__ == $0)
  ListHelper.handleCli(
    ['--auth',         '-a', 1],
    ['--check_lyrics', '-k', 0],
    ['--flat',         '-F', 0],
    ['--limit',        '-l', 1],
    ['--ofile',        '-o', 1],
    ['--exclude_user', '-x', 1],
  )
end
