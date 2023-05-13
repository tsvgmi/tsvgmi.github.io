# Extract video info (youtube)
class VideoInfo
  attr_reader :videos, :yk_videos

  def initialize(vstring, kstring=nil)
    yvideos = (vstring || '').split('|')
    vidkeys = (kstring || '').split('|')
    @yk_videos = yvideos.zip(vidkeys)
    check_videos
  end

  # Select set is "1/2/3"
  # If there is one or more solo index specified.  Use it since same song
  # could be played in multiple styles
  def select_set(solo_idx)
    if solo_idx && !@yk_videos.empty?
      solo_sel   = solo_idx.split('/').map(&:to_i)
      @yk_videos = @yk_videos.values_at(*solo_sel).compact
      # Plog.dump_info(solo_sel:solo_sel, yk_videos:@yk_videos)
      check_videos
    end
    @yk_videos
  end

  def check_videos
    @videos = []
    @yk_videos.each do |svideo, key|
      video, *ytoffset = svideo.split(',')
      ytoffset.each_slice(2) do |ytstart, ytend|
        ytstart = Regexp.last_match.pre_match.to_i * 60 + Regexp.last_match.post_match if ytstart =~ /:/
        ytend   = Regexp.last_match.pre_match.to_i * 60 + Regexp.last_match.post_match if ytend =~ /:/
        vid = "video_#{video.gsub(/[^a-z0-9_]/i, '')}_#{ytstart}_#{ytend}"
        # Plog.dump_info(vid:vid)
        @videos << {
          vid:, video:, key:,
          start: ytstart.to_i, end: ytend.to_i
        }
      end
    end
  end
end

