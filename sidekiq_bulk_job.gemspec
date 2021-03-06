require_relative 'lib/sidekiq_bulk_job/version'

Gem::Specification.new do |spec|
  spec.name          = "sidekiq_bulk_job"
  spec.version       = SidekiqBulkJob::VERSION
  spec.authors       = ["scalaview"]
  spec.email         = ["chailink100@gmail.com"]
  spec.summary       = %q{ Collect same jobs to single worker, reduce job number and improve thread utilization. }
  spec.description   = %q{Collect same jobs to single worker, reduce job number and improve thread utilization.}
  spec.homepage      = "https://github.com/scalaview/sidekiq_bulk_job"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency("sidekiq", "~> 5.2.7")
  spec.add_development_dependency("rspec-sidekiq", "~> 3.1.0")
  spec.add_development_dependency('pry', '~> 0.13.1')
end
