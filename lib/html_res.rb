# Common functions
module HtmlRes
  def get_page(url)
    require 'open-uri'

    # ENV['HTTPS_PROXY'] = 'http://poc1w80m7:8081'
    # ENV['HTTP_PROXY'] = 'http://poc1w80m7:8081'
    fid  = URI.parse(url).open
    page = Nokogiri::HTML(fid.read)
    # ENV.delete('HTTPS_PROXY')
    fid.close
    page
  end
end

