# Thor Extension
module ThorAddition
  def self.included(klass)
    klass.class_eval do
      def self.exit_on_failure?
        true
      end
    end
  end

  def cli_wrap
    if ENV['BYEBUG']
      say_status(Time.now, "#{File.basename(__FILE__)}:#{__LINE__} Entering debug mode", :yellow)
      ENV.delete('BYEBUG')
      require 'byebug'
      byebug
    end
    Signal.trap('SIGINT')  { exit(1) }
    Signal.trap('SIGQUIT') do
      Elog.info('Quitting from signal.')
      exit(0)
    end

    @logger = if options[:logfile]
                PLogger.new(value)
              else
                PLogger.new($stderr)
              end

    result = yield

    return(1) if result.is_a?(FalseClass)

    case result
    when TrueClass
      return(0)
    when String
      puts result
    else
      puts result.inspect
    end

    0
  end

  def writable_options
    options.transform_keys(&:to_sym)
  end
end

