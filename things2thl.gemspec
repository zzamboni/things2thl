# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{things2thl}
  s.version = "0.8.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Diego Zamboni"]
  s.date = %q{2009-05-25}
  s.default_executable = %q{things2thl}
  s.description = %q{Library and command-line tool for migrating Things data to The Hit List}
  s.email = %q{diego@zzamboni.org}
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
  s.has_rdoc = true
  s.homepage = %q{http://zzamboni.github.com/things2thl/}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Library and command-line tool for migrating Things data to The Hit List}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
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
