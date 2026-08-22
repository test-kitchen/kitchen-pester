require "bundler/gem_tasks"

require "rake/testtask"
Rake::TestTask.new(:unit) do |t|
  t.libs.push "lib", "spec"
  t.test_files = FileList["spec/**/*_spec.rb"]
  t.warning = true
  t.verbose = true
end

task test: :unit

begin
  require "cookstyle/chefstyle"
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:style) do |task|
    task.options += ["--display-cop-names", "--no-color"]
  end
rescue LoadError
  puts "cookstyle/chefstyle is not available. (sudo) gem install cookstyle to do style checking."
end

desc "Run all quality tasks"
task quality: :style

begin
  require "yard" unless defined?(YARD)
  YARD::Rake::YardocTask.new
rescue LoadError
  puts "yard is not available. (sudo) gem install yard to generate yard documentation."
end

task default: %i{test quality}

namespace :docs do
  desc "Deploy docs"
  task :deploy do
    sh "cd docs && hugo"
    sh "aws --profile chef-cd s3 sync docs/public s3://test-kitchen-legacy.cd.chef.co --delete --acl public-read"
    sh "aws --profile chef-cd cloudfront create-invalidation --distribution-id EQD8MRW086SRT --paths '/*'"
  end
end
