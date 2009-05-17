require 'rubygems'
require 'rake'
require 'echoe'

Echoe.new('things2thl', '0.1') do |p|
  p.description = "Library and command-line tool for migrating Things data to The Hit List"
  p.url         = "http://github.com/zzamboni/things2thl"
  p.author      = "Diego Zamboni"
  p.email       = "diego@zzamboni.org"
  p.development_dependencies = []
end

Dir["#{File.dirname(__FILE__)}/tasks/*.rake"].sort.each { |ext| load ext }
