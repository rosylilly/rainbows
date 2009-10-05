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

  s.add_dependency(%q<rack>)
  s.add_dependency(%q<unicorn>, ["~> 0.93.1"])

  # s.licenses = %w(GPLv2 Ruby) # accessor not compatible with older Rubygems
end
