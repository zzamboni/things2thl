# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{things2thl}
  s.version = "0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Diego Zamboni"]
  s.date = %q{2009-05-17}
  s.default_executable = %q{things2thl}
  s.description = %q{Library and command-line tool for migrating Things data to The Hit List}
  s.email = %q{diego@zzamboni.org}
  s.executables = ["things2thl"]
  s.extra_rdoc_files = ["README", "bin/things2thl", "lib/Things2THL.rb"]
  s.files = ["README", "Rakefile", "bin/things2thl", "lib/Things2THL.rb", "Manifest", "things2thl.gemspec"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/zzamboni/things2thl}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Things2thl", "--main", "README"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{things2thl}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Library and command-line tool for migrating Things data to The Hit List}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
