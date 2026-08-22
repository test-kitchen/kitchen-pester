# frozen_string_literal: true

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

require "yard"

# Generates the API docs into doc/. Options live in .yardopts so that this and
# a bare `yard` on the command line agree.
YARD::Rake::YardocTask.new(:yard) do |t|
  t.stats_options = ["--list-undoc"]
end

namespace :docs do
  desc "Generate the YARD documentation into doc/"
  task generate: :yard

  # Deliberately not wired into `quality` or CI -- run it when you want to
  # know, not as a gate on every build.
  desc "Report any class, module, constant or method that is undocumented"
  task :coverage do
    require "yard"
    YARD::Registry.clear
    YARD::CLI::Yardoc.run("--no-output", "--no-stats", "--no-progress")

    objects = YARD::Registry.all(:class, :module, :constant, :method)
    undocumented = objects.select { |o| o.docstring.to_s.strip.empty? }

    unless undocumented.empty?
      abort "Undocumented objects:\n#{undocumented.map { |o| "  #{o.path}" }.sort.join("\n")}"
    end

    puts "All #{objects.size} objects are documented."
  end

  desc "Deploy docs"
  task :deploy do
    sh "cd docs && hugo"
    sh "aws --profile chef-cd s3 sync docs/public s3://test-kitchen-legacy.cd.chef.co --delete --acl public-read"
    sh "aws --profile chef-cd cloudfront create-invalidation --distribution-id EQD8MRW086SRT --paths '/*'"
  end
end

desc "Run all quality tasks"
task quality: :style

task default: %i{test quality}
