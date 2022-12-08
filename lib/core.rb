#!/usr/bin/env ruby
# frozen_string_literal: true

#---------------------------------------------------------------------------
# File:        core.rb
# Date:        Tue Nov 13 15:52:52 -0800 2007
# $Id: core.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#++

# A laod file with more options
module YAML
  def self.safe_load_file(file, options={})
    options[:filename] = file
    load(File.read(file), options)
  end
end

def progress_set(wset, title=nil)
  title ||= caller[0].split.last.gsub(/['"`]/, '')
  tstring = format('%<title>-16.16s [:bar] :percent', title:)
  bar     = TTY::ProgressBar.new(tstring, total: wset.size)
  wset.each do |entry|
    break unless yield entry, bar

    bar.advance
  end
end

# Kernel extension
module Kernel
  #--------------------------------------------------------- def: hostname
  # Purpose  :
  #-----------------------------------------------------------------------
  def hostname(shortform: nil)
    require 'socket'

    if shortform
      Socket.gethostname.split('.').first
    else
      Socket.gethostname
    end
  end

  #--------------------------------------------------------- def: catcherr
  # Purpose  : Emulate the tcl catch command
  #-----------------------------------------------------------------------
  def catcherr
    yield
    0
  rescue StandardError
    1
  end

  # Check if class is main CLI facing class and extend cli support
  # module to it
  def extend_cli(_file)
    # if (file == $PROGRAM_NAME)
    include Cli
    extend  Cli
    # end
  end
end

