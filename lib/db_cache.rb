# DB Cache Definition
class DbCache
  class << self
    DBNAME = 'smule.db'

    def dbase
      @dbase ||= Sequel.sqlite(DBNAME)
    end
  end
end


