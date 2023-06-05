#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "#{File.dirname(__FILE__)}/../lib"

require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/partial'
require 'sinatra/flash'

require 'json'
require 'yaml'
require 'net/http'
require 'sequel'
require 'haml'

require_relative '../etc/toolenv'
require_relative '../lib/core'

require 'db_cache'
require 'sm_content'
require 'plog'

set :bind,            '0.0.0.0'
set :port,            (ENV['PORT'] || 4567).to_i
set :lock,            true
set :show_exceptions, true
set :server,          'thin'
set :root,            "#{File.dirname(__FILE__)}/.."
set :haml,            {escape_html: false}

enable :sessions

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# routes...
options '*' do
  response.headers['Allow'] = 'GET, POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token'
  response.headers['Access-Control-Allow-Origin'] = '*'
  200
end

get '/play-here' do
  ofile = params[:ofile]
  Plog.dump_info(ofile:)
  system("open -g \"#{ofile}\"") if test('f', ofile)
end

get '/smulelist/:user' do |user|
  content   = []
  singers   = {}
  smcontent = SmContent.new(user)
  records   = smcontent.content
  if !(days = params[:days]).nil? && ((days = days.to_i) > 0)
    records = records.where(created: Time.now - days * 24 * 3600..Time.now)
  end
  records.each do |r|
    record_by = r[:record_by].split(',')
    isfav     = r[:isfav] || r[:oldfav]
    content << r
    record_by.each do |asinger|
      siinfo = singers[asinger] ||= {name: asinger, count: 0, listens: 0,
                                     loves: 0, favs: 0}
      siinfo[:count]   += 1
      siinfo[:favs]    += 1 if isfav
      siinfo[:listens] += (r[:listens] || 0)
      siinfo[:loves]   += r[:loves].to_i
    end
  end
  Plog.dump_info(records:records)
  # Front end will also do sort, but we do on backend so content would
  # not change during initial display
  singers     = singers.values.sort_by { |r| r[:count] }.reverse
  all_singers = smcontent.singers
                          .as_hash(:name, [:avatar, :following, :follower])
  haml :smulelist, locals: {user:, singers:,
                            all_singers: all_singers,
                            join_me: smcontent.join_me,
                            i_join: smcontent.i_join}
end

get '/smulelist-perf/:user' do |user|
  # Plog.dump_info(params:params, _ofmt:'Y')
  start     = params[:start].to_i
  length    = (params[:length] || 10_000).to_i
  order     = (params[:order] || {}).values.first || {'column' => 5, 'dir' => 'desc'}
  days      = params[:days].to_i
  Plog.info "Content again - perf"
  smcontent = SmContent.new(user)

  columns = %i[title isfav record_by listens loves created]
  records = smcontent.content
  records = records.left_join(smcontent.songinfos, song_info_url: :song_info_url)
  records = get_searches(records)
  records = records.where(created: Time.now - days * 24 * 3600..Time.now) if days > 0

  data0     = records
  ocolumn   = order['column'].to_i
  data0 = if order['dir'] == 'desc'
            data0.reverse(columns[ocolumn])
          else
            data0.order(columns[ocolumn])
          end
  # Plog.dump_info(search:search)

  data = data0.limit(length).offset(start)

  # Plog.dump_info(data:data.sql, data0:data0.sql)
  locals = {
    total:    records.count,
    filtered: data0.count,
    user:,
    data:,
  }
  yaml_src = erb(File.read('views/smule_data.yml'), locals:)
  data = YAML.safe_load(yaml_src)
  data['data'] ||= []
  data.to_json
end

get '/player/:sid' do |sid|
  ofile = '../hacauto/toplay.dat'
  File.open(ofile, 'a') do |fod|
    fod.puts sid
  end
end

get '/smulegroup2/:user' do |user|
  haml :smulegroup2, locals: {user:}
end

get '/smgroups_data/:user' do |user|
  # Plog.dump_info(params: params)
  Plog.dump_info(order: params[:order])
  start     = params[:start].to_i
  length    = (params[:length] || 1).to_i
  order     = (params[:order] || {}).values.first || {'column' => 2, 'dir' => 'desc'}
  # search    = (params[:search] || {})['value']

  smcontent = SmContent.new(user)
  columns   = %i[stitle record_by created tags listens loves]
  records   = smcontent.content.left_join(smcontent.songinfos, song_info_url: :song_info_url)

  data0     = records
  data0     = get_searches(data0)
  ocolumn   = order['column'].to_i
  odir      = order['dir']
  fmap      = %w[stitle record_by created tags]
  data0     = data0.group(:stitle)
  Plog.dump_info(query: data0, count: data0.count)
  total     = data0.count

  filtered  = data0.count

  Plog.dump_info(query: data0, count: data0.count)
  data0 = if odir == 'desc'
            data0.reverse(fmap[ocolumn])
          else
            data0.order(fmap[ocolumn])
          end
  stitles = data0.group(:stitle).map { |r| r[:stitle] }
  data0   = data0.limit(length).offset(start)
  Plog.dump_info(query: data0, count: data0.count)

  # data = records.where(stitle: stitles).reverse(:created)
  data = records.where(stitle: stitles[start..start + length - 1])
  data = if odir == 'desc'
           data.reverse(fmap[ocolumn])
         else
           data.order(fmap[ocolumn])
         end
  Plog.dump_info(query: data, count: data.count)
  data = data.map { |r| r }.group_by { |r| r[:stitle] }
             .reject do |_stitle, sinfos|
    sinfos.find { |sinfo| sinfo[:record_by] == user }
  end

  ndata = {}
  data.each do |stitle, slist|
    ndata[stitle] = {
      listens:   slist.inject(0) { |sum, x| sum + x[:listens] },
      loves:     slist.inject(0) { |sum, x| sum + x[:loves] },
      tags:      slist.inject([]) { |sum, x| sum << x[:tags] }
                      .join(',').split(',').uniq.join(', '),
      created:   slist[0][:created],
      stitle:    slist[0][:stitle],
      record_by: slist[0][:record_by],
      list:      slist,
    }
  end
  ndata = ndata.to_a.sort_by { |r| r[1][columns[ocolumn]] }
  ndata = ndata.reverse if order['dir'] == 'desc'

  locals = {
    total:,
    filtered:,
    user:,
    data:     ndata,
    all_singers: smcontent.singers,
  }
  yaml_src = erb(File.read('views/smgroups_data.yml'), locals:)
  YAML.safe_load(yaml_src).to_json
end

get '/smulegroup/:user' do |user|
  content   = []
  singer    = (params[:singer] || '').split
  tags      = (params[:tags] || '').split.join('|')
  tags      = tags.empty? ? nil : Regexp.new(tags)
  smcontent = SmContent.new(user)
  records   = smcontent.content.left_join(smcontent.songinfos, song_info_url: :song_info_url)
                       .reverse(:created)
  records.each do |r|
    unless singer.empty?
      record_by = r[:record_by].split(',')
      next if (record_by & singer).empty?
    end
    next if params[:title] && r[:title] != params[:title]

    next if tags && r[:tags] !~ tags

    content << r
  end
  scontent = content.group_by { |r| r[:title].downcase.sub(/\s*\(.*$/, '') }
  haml :smulegroup, locals: {user:, scontent:,
                             all_singers: smcontent.singers}
end

KEY_POS = %w[A A#|Bb B C C#|Db D D#|Eb E F F#|Gb G G#|Ab].freeze
helpers do
  def get_searches(records)
    searches = if params[:search_c] && !params[:search_c].empty?
                 [params[:search_c]]
               else
                 (params[:search] || {})['value'].split(',')
               end

    dsearches = []
    searches.each do |search|
      next if search.empty?

      case search
      when /^f:/
        records = records.filter(isfav: true).or(oldfav: true)
      when /^o:/
        records = records.where(Sequel.lit("href like '%ensembles'"))
      when /^t:/
        dsearches << [%w[tags author singer], Regexp.last_match.post_match]
      when /^s:/
        dsearches << [%w[sfile], Regexp.last_match.post_match]
      when /^r:/
        dsearches << [%w[record_by], Regexp.last_match.post_match]
      when /^c:/
        dsearches << [%w[orig_city other_city], Regexp.last_match.post_match]
      else
        dsearches << [%w[performances.stitle record_by], search]
      end
    end
    # Plog.dump_info(searches:searches, dsearches:dsearches)

    dsearches.each do |sfields, search|
      search = search.downcase.gsub(/_/, '/_')
      pdata   = []
      query   = sfields.map do |f|
        pdata << "%#{search}%"
        "LOWER(#{f}) like ? escape '/'"
      end.join(' or ')
      records = records.where(Sequel.lit(query, *pdata))
    end
    Plog.dump_info(records:, count: records.count)
    records
  end
end

