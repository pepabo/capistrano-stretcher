# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "capistrano-stretcher"
  spec.version       = "0.3.0"
  spec.authors       = ["SHIBATA Hiroshi", "Uchio Kondo"]
  spec.email         = ["hsbt@ruby-lang.org", "udzura@udzura.jp"]

  spec.summary       = %q{capistrano task for stretcher.}
  spec.description   = %q{capistrano task for stretcher.}
  spec.homepage      = "https://github.com/pepabo/capistrano-stretcher"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'capistrano', '>= 3'

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
end
