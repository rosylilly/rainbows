# -*- encoding: binary -*-

ENV["VERSION"] or abort "VERSION= must be specified"
manifest = File.readlines('.manifest').map! { |x| x.chomp! }

# don't bother with tests that fork, not worth our time to get working
# with `gem check -t` ... (of course we care for them when testing with
# GNU make when they can run in parallel)
test_files = manifest.grep(%r{\Atest/unit/test_.*\.rb\z}).map do |f|
  File.readlines(f).grep(/\bfork\b/).empty? ? f : nil
end.compact

Gem::Specification.new do |s|
  s.name = %q{rainbows}
  s.version = ENV["VERSION"]

  s.authors = ["Rainbows! developers"]
  s.date = Time.now.utc.strftime('%Y-%m-%d')
  s.description = File.read("README").split(/\n\n/)[1]
  s.email = %q{rainbows-talk@rubyforge.org}
  s.executables = %w(rainbows)

  s.extra_rdoc_files = File.readlines('.document').map! do |x|
    x.chomp!
    if File.directory?(x)
      manifest.grep(%r{\A#{x}/})
    elsif File.file?(x)
      x
    else
      nil
    end
  end.flatten.compact

  s.files = manifest
  s.homepage = %q{http://rainbows.rubyforge.org/}
  s.summary = %q{Unicorn for sleepy apps and slow clients}
  s.rdoc_options = [ "-Na", "-t", "Rainbows! #{s.summary}" ]
  s.require_paths = %w(lib)
  s.rubyforge_project = %q{rainbows}

  s.test_files = test_files

  # we need Unicorn for the HTTP parser and process management
  # Unicorn 0.95.0 should be released on or around Nov 13/14/15, 2009
  s.add_dependency(%q<unicorn>, ["~> 0.95.0"])

  # Unicorn already depends on Rack
  # s.add_dependency(%q<rack>)

  # optional runtime dependencies depending on configuration
  # see local.mk.sample for the exact versions we've tested with
  #
  # Revactor >= 0.1.5 includes UNIX domain socket support
  # s.add_dependency(%q<revactor>, [">= 0.1.5"])
  #
  # Revactor depends on Rev, too, 0.3.0 got the ability to attach IOs
  # s.add_dependency(%q<rev>, [">= 0.3.0"])
  #
  # We use the new EM::attach/watch API in 0.12.10
  # s.add_dependency(%q<eventmachine>, ["~> 0.12.10"])

  # s.licenses = %w(GPLv2 Ruby) # accessor not compatible with older Rubygems
end
