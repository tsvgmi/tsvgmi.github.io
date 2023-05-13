# Functions to support CLI interaction (i.e. options processing,
# help, result interpretation, exit handling)
module Cli
  def set_options(opt)
    @options ||= {}
    @options.merge!(opt)
  end

  def get_option(name=nil)
    @options ||= {}
    name ? @options[name] : @options
  end

  # Common handling of most CLI facing script.  It parse the command
  # line, set to class option, invoke class method if so specified.
  # If not, it yield back to object handler.  It then process the
  # result for output back to the shell.
  #
  # Processing is as followed:
  # * If --class option is specified, or if the class does not have
  #   any instance method, the command will be sent to class method
  # * If there is a processing block, yield(opt) is called to let
  #   the class handle the argument parsing.
  # * If the class respond to cliNew to instantiate default cli object,
  #   it will be called to instantiate an instance, and the rest of
  #   arguments sent to it
  # * Otherwise, the first argument is used as parameter to the
  #   object instantiation, and the rest of the argument is passed to
  #   it.
  #
  # Return handling (from class/object)
  #
  # * If the class support cliResult method, it will be called with
  #   the result and object (for instance invocation).
  # * Otherwise, a default handling of the result is done (i.e.
  #   printing of output and set exit cod)
  def handle_cli(*optset)
    imethods = instance_methods(false)
    optset << ['--class', '-c'] unless imethods.empty?
    @cli_options = optset
    opt = Cli.parse_options(*optset)
    set_options(opt)
    obj = nil
    if opt[:class] || (imethods.size <= 0)
      !ARGV.empty? || cli_usage
      method = ARGV.shift.gsub(/-/, '_')
      result = send(method, *ARGV)
    elsif block_given?
      result = yield opt
    # Class handle CLI instantiation?
    elsif respond_to?(:cliNew)
      # ARGV could change during cliNew, so we check both places
      !ARGV.empty? || cli_usage
      obj = cliNew
      !ARGV.empty? || cli_usage
      method = ARGV.shift.gsub(/-/, '_')
      result = obj.send(method, *ARGV)
    else
      !ARGV.empty? || cli_usage
      obj    = new(ARGV.shift)
      method = ARGV.shift.gsub(/-/, '_')
      result = obj.send(method, *ARGV)
    end

    # Class handle result?
    if respond_to?(:cli_result)
      cli_result(result, obj)
    else
      Cli.shell_result = result
    end
  end

  # Print the message on cli usage (flag/method) and exit script
  def cli_usage
    warn "#{File.basename($PROGRAM_NAME)} #{Cli.show_options(@cli_options).join(' ')} [object] method ...'
    Cli.class_usage(self)
  end

  # Print a prompt and wait for y/n answer
  def self.confirm(prompt, default='n')
    $stderr.print " # {prompt} (y/n) [n]? "
    ans = $stdin.gets
    ans = default if !ans || (ans == '')
    ans =~ /[Yy]/ ? true : false
  end

  # Print a message and just wait till user press enter
  def self.pause(msg='... Press return to continue ...')
    $stderr.print msg
    $stdin.gets
  end

  # Similar to ksh select functionality.  Select a member from an
  # input list
  def self.select(alist, aprompt=nil)
    maxwidth = 10
    alist.each do |entry|
      maxwidth = entry.size if entry.size > maxwidth
    end
    swidth = ENV['COLUMNS'] || 80
    swidth = swidth.to_i - 2
    cols   = swidth / (maxwidth + 5)
    cols   = 1 if cols <= 0
    pwidth = (swidth / cols) - 5
    pcol   = (alist.size + cols - 1) / cols
    loop do
      0.upto(pcol - 1) do |ridx|
        0.upto(cols - 1) do |cidx|
          idx   = ridx + cidx * pcol
          entry = alist[idx]
          $stderr.print(format("%2d. %-#{pwidth}s ", idx + 1, entry)) if entry
        end
        $stderr.puts
      end
      if block_given?
        ans = yield
      else
        $stderr.print "#{aprompt}: "
        ans = $stdin.gets
      end
      return nil unless ans

      ans.chomp!
      next if ans == ''
      return alist[ans.to_i - 1] if ans =~ /^[0-9]+$/

      break
    end
    nil
  end

  # Print the usage message for the class (instance and class methods)
  # to be used in display help
  def self.class_usage(klass)
    defs = {}
    mlist = klass.instance_methods(false).grep(/^[^_]/).map do |amethod|
      ['', amethod, klass.instance_method(amethod).arity]
    end +
            (klass.singleton_methods - Cli.instance_methods).map do |amethod|
              ["#{klass}.", amethod, klass.method(amethod).arity]
            end
    mlist.sort.each do |c, f, m|
      if defs[f]
        warn "  - #{c}#{f}(#{defs[f]})"
      else
        vlist =
          if m < 0
            "#{Array.new(-m, 'v').join(', ')}, ..."
          else
            Array.new(m, 'v').join(', ')
          end
        warn "  - #{c}#{f}(#{vlist})"
      end
    end
    $stderr.print "<Return> to quit or 'h' for help ..."
    result = $stdin.gets.chomp
    exit unless result =~ /^[hH]/
    exec "tman -r #{$PROGRAM_NAME}"
  end

  # Wait for an interval seconds and print progress dot ...
  def self.wait(interval, comment=nil)
    $stderr.print comment.to_s if comment
    $stderr.print "[#{interval}]: "
    interval.downto(1) do
      $stderr.print '.'
      $stderr.flush
      sleep(1)
    end
    warn ''
  end

  # Map output to shell (at exit) for ruby class output
  def self.shell_result(result)
    case result
    when TrueClass
      exit(0)
    when FalseClass
      exit(1)
    when String
      puts result
    else
      puts result.inspect
    end
    exit(0)
  end

  def self.show_options(options)
    options.map do |long, short, type, _default|
      if type == 1
        "[#{long}|#{short} value]"
      else
        "[#{long}|#{short}]"
      end
    end
  end

  # Similar to parse, but model after perl getopt - i.e. all setting
  # is done to a returned hash.  That way, actual handling for option
  # could be defered, or the hash could be used directly as part of
  # the runtime configuration
  #
  # options is a list of tuple: long name, short name, type, default
  def self.parse_options(*options)
    require 'getoptlong'

    option = {}
    newopt = options.collect do |optspec|
      opt, tmp, type, default = optspec
      if type.nil?
        type = GetoptLong::NO_ARGUMENT
        optspec[2] = type
      end
      optname = opt[2..]
      option[optname.intern] = default
      [opt, tmp, type]
    end
    begin
      GetoptLong.new(*newopt).each do |opt, arg|
        optname = opt[2..]
        option[optname.intern] = arg == '' ? true : arg
      end
    rescue StandardError => e
      puts e
      puts "#{File.basename($PROGRAM_NAME)} #{show_options(options).join(' ')} ...."
    end
    option
  end
end

