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
require 'micromidi'
require 'core'

# BKSet Definition
class BKSet
  extend_cli __FILE__

  # Tone Settings
  class ToneSetting
    class << self
      TONE_DIR   = "#{ENV['HOME']}/myprofile/etc".freeze
      INSTRUMENT = 'bk50'

      def _load_soundlist(file)
        defs = {}
        File.read(file).split("\n").each do |l|
          fs = l.split
          next unless fs.size >= 5

          sno = fs[0]
          c0 = fs[-3]
          c32 = fs[-2]
          ch = fs[-1]
          name = fs[1..-4].join(' ')
          defs[sno] = {name:, send: "#{c0}.#{c32}.#{ch}", sno:}
        end
        defs
      end

      def sound(sname)
        sname = format('%04d', sname.to_i)
        @sdefs ||= _load_soundlist("#{TONE_DIR}/sounds-#{INSTRUMENT}.dat")
        ret = @sdefs[sname]
        Plog.error("#{sname} not found") unless ret
        ret
      end

      def rhymth(rname)
        rname = format('%04d', rname.to_i)
        @rdefs ||= _load_soundlist("#{TONE_DIR}/rhymths-#{INSTRUMENT}.dat")
        ret = @rdefs[rname]
        Plog.error("#{rname} not found") unless ret
        ret
      end
    end
  end

  # handle of Midi play
  class MidiPlay
    def self.instance
      @mobj ||= MidiPlay.new
      @mobj
    end

    def initialize
      @o    = UniMIDI::Output.use(:first)
      @midi = MIDI::Session.new(@o)
    end

    NOTES = %w[C C#|Db D D#|Eb E F F#|Gb G G#|Ab A A#|Bb B].freeze
    MAJOR = [0, 4, 7].freeze
    MINOR = [0, 3, 7].freeze

    def notes_for_chord(key)
      mset     = key[-1] == 'm' ? MINOR : MAJOR
      base_ofs = NOTES.index { |n| key =~ /^#{n}/ }
      unless base_ofs
        Plog.error "Unknown key: #{key}"
        return []
      end
      notes = mset.map do |interval|
        offset = (base_ofs + interval) % NOTES.size
        snote  = NOTES[offset].split('|')[0]
        ["#{snote}4", "#{snote}5"]
      end
      notes.flatten
    end

    def sselect(plist, sounding: true)
      # Plog.info({plist:plist}.inspect)
      sendc = 0
      %i[lower upper rhymth].each do |atype|
        unless (value = plist[atype]).nil?
          send_pc(atype, value)
          sendc += value.size
        end
      end
      unless (value = plist[:pchange]).nil?
        @midi.program_change value.to_i - 1
        sleep 0.1
      end

      sound_chord(plist[:key] || 'C') if sounding
      @midi.parse([0xfa]) if plist[:rhymth]
    end

    CHANNEL_MAP = {
      drum:   9,
      lower:  10,
      rhymth: 0, # Must set in keyboard everytime
      upper:  3,
    }.freeze
    def send_pc(mtype, unos)
      chan = CHANNEL_MAP[mtype]
      @midi.channel chan
      unos.each do |uno|
        Plog.info "C#{chan} - #{mtype}: #{uno.inspect}"
        b0, b1, c = uno[:send].split('.')
        @midi.control_change 0, b0.to_i
        @midi.control_change 32, b1.to_i
        @midi.program_change c.to_i - 1
        sleep 0.1
      end
    end

    def sound_chord(key)
      sound_notes(notes_for_chord(key))
    end

    def sound_notes(notes)
      Plog.dump_info(notes:)
      notes.each do |ano|
        @midi.note ano
      end
      sleep 1
      @midi.control_change 0x7b, 0 # All notes off
    end
  end

  class << self
    def apply_settings(midiplay, sinfo, sounding: true)
      # Sort/reverse is needed so I don't intone the percussion
      htones = (sinfo[:htones] || []).sort.reverse
                                     .map { |htone| ToneSetting.sound(htone) }
      ltone  = ToneSetting.sound(sinfo[:ltone])
      rhymth = ToneSetting.rhymth(sinfo[:rhymth])
      plist = {upper: htones, lower: ltone ? [ltone] : nil,
               rhymth: rhymth ? [rhymth] : nil,
               key: sinfo[:key]}
      midiplay.sselect(plist, sounding:)
      plist
    end

    def load_setlist(flist)
      smap  = {}
      lcnt  = 0
      cnames = YAML.load_file(flist).sort_by do |r|
        r[:href] ? r[:href].split('/')[5] : r[:name].downcase
      end
      cnames.each_with_index do |sentry, index|
        song = sentry[:name].strip[0..31]
        if sentry[:sound]
          htones, ltone, rhymth = sentry[:sound].to_s.split(',')
          skey = "#{index + 1}.#{song}"
          smap[skey] = {
            htones: (htones || '').split('/'),
            ltone:,
            rhymth:,
          }
        else
          skey = "-#{index + 1}.#{song}"
          smap[skey] = {}
        end
        smap[skey].update({
                            index:    lcnt + 1,
          key:      sentry['key'],
          playnote: sentry['playnote'],
                          })
        lcnt += 1
      end
      smap
    end

    def apply_midi(set_str)
      require 'json'

      options = get_option
      htones, ltone, rhymth = set_str.split(',')
      htones   = htones.split(%r{[/+]})
      setup    = {
        htones:, ltone:, rhymth:, key: options[:key]
      }
      Plog.dump_info(setup:)
      midiplay = MidiPlay.instance
      plist = apply_settings(midiplay, setup, sounding: true)
      plist.to_json
    end

    def handle_setloop(smap_keys)
      aprompt = 'Select song to load [R|b|c..|l..|r..|u..]'
      Cli.select(smap_keys) do
        ans = nil
        loop do
          $stderr.print "#{aprompt}: "
          ans = $stdin.gets.chomp
          case ans
          when /^R/
            $0   = 'Running' #                     Mangle $0 to disable init code
            file = __FILE__
            # rubocop:disable Security/Eval
            begin
              eval "load '#{file}'", TOPLEVEL_BINDING, __FILE__, __LINE__
            rescue StandardError => e
              Plog.error e
            end
            # rubocop:enable Security/Eval
          when /^b/i
            require 'byebug'
            byebug
          when /^u/
            htones = Regexp.last_match.post_match.split('/').map { |sno| ToneSetting.sound(sno.strip) }
            midiplay.sselect(upper: htones) if htones
          when /^l/
            ltone = ToneSetting.sound(Regexp.last_match.post_match.strip)
            midiplay.sselect(lower: [ltone]) if ltone
          when /^r/
            rhymth = ToneSetting.rhymth(Regexp.last_match.post_match.strip)
            midiplay.sselect(rhymth: [rhymth]) if rhymth
          when /^c/
            midiplay.sselect(pchange: Regexp.last_match.post_match)
          when /^x/
            break
          end
        end
        ans
      end
    end

    def setloop(flist)
      smtime   = Time.at(0)
      midiplay = MidiPlay.instance
      puts <<~EOF
        Roland BK-50 Midi SetList.
        *** Remember to set rhymth in MIDI section every power on ***
      EOF
      loop do
        if File.mtime(flist) > smtime
          Plog.info("#{flist} changed.  Reload")
          smap   = load_setlist(flist)
          smtime = File.mtime(flist)
        end
        unless (song = handle_setloop(smap.keys.sort))
          break
        end

        Plog.info("Selecting #{song}: #{smap[song].inspect}")
        apply_settings(midiplay, smap[song])
      end
    end
      end
end

if __FILE__ == $PROGRAM_NAME
  BKSet.handle_cli(
    ['--channel', '-C', 1],
    ['--key',     '-k', 1]
  )
end
