# DB Cache Definition
class DbCache
  class << self
    def dbase
      unless @dbase
        db = ENV['DB'] || 'local'
        config = YAML.load_file('etc/dbase.yml')[db]
        unless config
          raise "No definition for DB #{db} found"
        end
        dbconfig = config[:config].update(adapter:config[:type])
        Plog.dump_info(dbconfig:dbconfig)
        @dbase = Sequel.connect(dbconfig)
        @dbase.loggers << Logger.new('dbase.log', 'monthly')
        @dbase.sql_log_level = :debug
      end
      @dbase
    end
  end
end


