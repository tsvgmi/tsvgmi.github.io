# SM Content Definition
class SmContent
  def initialize(user)
    @user    = user
  end

  def build_joins
    @i_join, @join_me = {}, {}
    content.each do |r|
      rby = r[:record_by].split(',')
      if rby[0] == @user
        other = rby[1]
        @join_me[other] ||= 0
        @join_me[other] += 1
      end
      next unless rby[1] == @user

      other = rby[0]
      @i_join[other] ||= 0
      @i_join[other] += 1
    end
  end

  def join_me
    build_joins unless @join_me
    @join_me
  end

  def i_join
    build_joins unless @i_join
    @i_join
  end

  def content
    DbCache.dbase[:performances]
           .where(deleted: nil).or(deleted: 0)
           .where(Sequel.lit("record_by like '%#{@user}%'"))
  end

  def singers
    DbCache.dbase[:singers]
  end

  def songinfos
    DbCache.dbase[:song_infos]
  end

  def remove(sid)
    Plog.info("Deleting #{sid}")
    content.where(sid:).delete
    true
  end
end


