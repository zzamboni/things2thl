require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "things2thl"
    gemspec.summary = "Library and command-line tool for migrating Things data to The Hit List"
    gemspec.email = "diego@zzamboni.org"
    gemspec.homepage = "http://zzamboni.github.com/things2thl/"
    gemspec.description = "Library and command-line tool for migrating Things data to The Hit List"
    gemspec.authors = ["Diego Zamboni"]
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

Dir["#{File.dirname(__FILE__)}/tasks/*.rake"].sort.each { |ext| load ext }
