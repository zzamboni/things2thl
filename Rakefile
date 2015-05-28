require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "things2thl"
    gemspec.summary = "Migrating Things data to The Hit List"
    gemspec.email = "diego@zzamboni.org"
    gemspec.license = "MIT"
    gemspec.homepage = "http://zzamboni.org/things2thl/"
    gemspec.description = "Library and command-line tool for migrating Things data to The Hit List"
    gemspec.authors = ["Diego Zamboni"]
    gemspec.add_dependency('rb-appscript', '>=0.5.1')
    gemspec.add_dependency('hpricot', '>=0.6')
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

Dir["#{File.dirname(__FILE__)}/tasks/*.rake"].sort.each { |ext| load ext }
