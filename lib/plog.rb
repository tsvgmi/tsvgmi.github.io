# --- Class: Plog
require 'logger'

# PLogger handling
class PLogger < Logger
  FORMAT2 = "%<sev>s %<time>s - [%<script>s] %<msg>s\n"
  attr_accessor :simple, :clevel

  def initialize(*args)
    super
    @simple = false
    @slevel = 2
    @clevel = 0
  end

  def format_message(severity, timestamp, progname, msg)
    # Look like this changes from diff versions.  So we need to detect
    script = caller[@slevel + @clevel].sub(/:in .*$/, '').sub(%r{^.*/}, '')
    if @simple
      format("%<sev>s - [%<script>s] %<msg>s\n",
             sev: severity[0..0], script:, msg:)
    elsif timestamp.respond_to?(:strftime)
      format(FORMAT2, sev: severity[0..0], time: timestamp.strftime('%y/%m/%d %T'),
             script:, msg:)
    else
      format(FORMAT2, sev: severity[0..0], time: timestamp,
             script:, msg: progname)
    end
  end

  def _fmt_obj(obj)
    msg =
      if obj[:_ofmt] == 'Y'
        obj.to_yaml
      else
        obj.inspect
      end
    @clevel = 3
    yield msg
    @clevel = 0
  end

  def dump_info(obj)
    _fmt_obj(obj) { |msg| info(msg) }
  end

  def dump_error(obj)
    _fmt_obj(obj) { |msg| error(msg) }
  end

  def dump(obj)
    _fmt_obj(obj) { |msg| debug(msg) }
  end
end

#     Singleton class for application based global log
class Plog
  TIMESTAMP_FMT = '%Y-%m-%d %H:%M:%S'
  class << self
    private

    def my_logs
      # Beside singleton imp,  this is also done to defer log creation
      # to absolute needed to allow application to control addition
      # logger setting
      @my_logs ||= set_logger
    end

    public

    def set_logger
      logspec = (ENV['LOG_LEVEL'] || '')
      logger = if logspec =~ /:f/
                 PLogger.new(Regexp.last_match.post_match.sub(/:.*$/, ''))
               else
                 PLogger.new($stderr)
               end
      log_level, *logopts = logspec.split(':')
      logopts.each do |anopt|
        oname = anopt[0]
        # ovalue = anopt[1..]
        case oname
        when 's'
          logger.simple = true
        end
      end
      logger.level = if log_level && !log_level.empty?
                       log_level.to_i
                     else
                       Logger::INFO
                     end
      logger.datetime_format = TIMESTAMP_FMT
      @my_logs = logger
    end

    def _fmt_obj(obj)
      msg =
        if obj[:_ofmt] == 'Y'
          obj.to_yaml
        else
          obj.inspect
        end
      my_logs.clevel = 3
      yield msg
      my_logs.clevel = 0
    end

    def dump_info(obj)
      _fmt_obj(obj) { |msg| my_logs.info(msg) }
    end

    def dump_error(obj)
      _fmt_obj(obj) { |msg| my_logs.error(msg) }
    end

    def dump(obj)
      _fmt_obj(obj) { |msg| my_logs.debug(msg) }
    end

    def method_missing(symbol, *args)
      my_logs.clevel = 1
      result = my_logs.send(symbol, *args)
      my_logs.clevel = 0
      result
    end

    def respond_to_missing?(_method_name, _include_private=false)
      true
    end
  end
end


