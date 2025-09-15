# frozen_string_literal: true

require_relative "lib/a2a/version"

Gem::Specification.new do |spec|
  spec.name = "a2a-ruby"
  spec.version = A2A::VERSION
  spec.authors = ["A2A Ruby Team"]
  spec.email = ["team@a2a-ruby.org"]

  spec.summary = "Agent2Agent (A2A) Protocol implementation for Ruby"
  spec.description = "Complete A2A Protocol implementation for Ruby applications, enabling agent-to-agent communication via JSON-RPC 2.0, gRPC, and HTTP+JSON transports"
  spec.homepage = "https://github.com/traylinx/a2a-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/traylinx/a2a-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/traylinx/a2a-ruby/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://a2a-protocol.org/latest/sdk/ruby/"

  # Specify which files should be added to the gem when it is released
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features|coverage)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  
  # Include essential documentation
  spec.files += %w[
    README.md
    CHANGELOG.md
    LICENSE.txt
    CODE_OF_CONDUCT.md
    CONTRIBUTING.md
  ]
  
  # Include documentation directory
  spec.files += Dir["docs/**/*.md"]
  
  # Include examples
  spec.files += Dir["examples/**/*.rb"]
  
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core runtime dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "jwt", "~> 2.0"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  
  # Optional dependencies for enhanced functionality
  spec.add_dependency "redis", ">= 4.0", "< 6.0"
  
  # Rails integration (optional)
  spec.add_dependency "railties", ">= 6.0", "< 8.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.0"
  
  # Code quality and linting
  spec.add_development_dependency "rubocop", "~> 1.57"
  spec.add_development_dependency "rubocop-rspec", "~> 2.25"
  spec.add_development_dependency "rubocop-performance", "~> 1.19"
  
  # Coverage and documentation
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "yard", "~> 0.9"
  
  # Performance testing
  spec.add_development_dependency "benchmark-ips", "~> 2.12"
  
  # Development tools
  spec.add_development_dependency "rake", "~> 13.0"
end