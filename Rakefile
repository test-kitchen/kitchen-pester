# -*- encoding: utf-8 -*-

require "bundler/gem_tasks"

require "rake/testtask"
Rake::TestTask.new(:unit) do |t|
  t.libs.push "lib"
  t.test_files = FileList["spec/**/*_spec.rb"]
  t.verbose = true
end

task test: :unit

begin
  require "chefstyle"
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:style) do |task|
    task.options += ["--display-cop-names", "--no-color"]
  end
rescue LoadError
  puts "chefstyle is not available. (sudo) gem install chefstyle to do style checking."
end

desc "Run all quality tasks"
task quality: :style

begin
  require "yard"
  YARD::Rake::YardocTask.new
rescue LoadError
  puts "yard is not available. (sudo) gem install yard to generate yard documentation."
end

task default: %i{test quality}

begin
  require "github_changelog_generator/task"
  require "kitchen/verifier/pester_version"

  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.future_release = "v#{Kitchen::Verifier::PESTER_VERSION}"
    config.issues = false
    config.pulls = true
    config.user = "test-kitchen"
    config.project = "kitchen-pester"
  end
rescue LoadError
  puts "github_changelog_generator is not available." \
       " (sudo) gem install github_changelog_generator to generate changelogs"
end

namespace :docs do
  desc "Deploy docs"
  task :deploy do
    sh "cd docs && hugo"
    sh "aws --profile chef-cd s3 sync docs/public s3://test-kitchen-legacy.cd.chef.co --delete --acl public-read"
    sh "aws --profile chef-cd cloudfront create-invalidation --distribution-id EQD8MRW086SRT --paths '/*'"
  end
end
