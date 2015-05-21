# -*- encoding: utf-8 -*-

require "bundler/gem_tasks"

require "rake/testtask"
Rake::TestTask.new(:unit) do |t|
  t.libs.push "lib"
  t.test_files = FileList["spec/**/*_spec.rb"]
  t.verbose = true
end

desc "Run all test suites"
task :test => [:unit]

desc "Display LOC stats"
task :stats do
  puts "\n## Production Code Stats"
  sh "countloc -r lib"
  puts "\n## Test Code Stats"
  sh "countloc -r spec"
end

require "finstyle"
require "rubocop/rake_task"
RuboCop::RakeTask.new(:style) do |task|
  task.options << "--display-cop-names"
  task.options << "--lint"
  task.options << '--config' << '.rubocop.yml'
  task.patterns = ['lib/**/*.rb']
end

require "cane/rake_task"
desc "Run cane to check quality metrics"
Cane::RakeTask.new do |cane|
  cane.canefile = "./.cane"
end

desc "Run all quality tasks"
task :quality => [:cane, :style, :stats]

require "yard"
YARD::Rake::YardocTask.new

desc "Generate gem dependency graph"
task :viz do
  Bundler.with_clean_env do
    sh "bundle viz --without test development guard " \
      "--requirements --version"
  end
end

task :default => [:test, :quality]
