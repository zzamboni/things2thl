# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: things2thl 0.8.6 ruby lib

Gem::Specification.new do |s|
  s.name = "things2thl"
  s.version = "0.8.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Diego Zamboni"]
  s.date = "2015-05-28"
  s.description = "Library and command-line tool for migrating Things data to The Hit List"
  s.email = "diego@zzamboni.org"
  s.executables = ["things2thl"]
  s.extra_rdoc_files = [
    "ChangeLog",
    "README"
  ]
  s.files = [
    "ChangeLog",
    "Manifest",
    "README",
    "Rakefile",
    "VERSION",
    "bin/things2thl",
    "lib/Things2THL.rb",
    "things2thl.gemspec"
  ]
  s.homepage = "http://zzamboni.org/things2thl/"
  s.licenses = ["MIT"]
  s.rubygems_version = "2.4.5"
  s.summary = "Migrating Things data to The Hit List"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rb-appscript>, [">= 0.5.1"])
      s.add_runtime_dependency(%q<hpricot>, [">= 0.6"])
    else
      s.add_dependency(%q<rb-appscript>, [">= 0.5.1"])
      s.add_dependency(%q<hpricot>, [">= 0.6"])
    end
  else
    s.add_dependency(%q<rb-appscript>, [">= 0.5.1"])
    s.add_dependency(%q<hpricot>, [">= 0.6"])
  end
end

