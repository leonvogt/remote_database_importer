# frozen_string_literal: true

require_relative "lib/remote_database_importer/version"

Gem::Specification.new do |spec|
  spec.name = "remote_database_importer"
  spec.version = RemoteDatabaseImporter::VERSION
  spec.authors = ["Leon Vogt"]
  spec.email = ["nonick@nonick.ch"]

  spec.summary = "Dump remote databases and import it locally"
  spec.description = "Dump remote databases and import it locally. At the moment only Postgres databases are supported"
  spec.homepage = "https://github.com/leon-vogt/remote_database_importer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "bin"
  spec.require_paths = ["lib"]

  spec.add_dependency "tty-config", "~> 0.6"
  spec.add_dependency "tty-spinner", "~> 0.9.3"
end
