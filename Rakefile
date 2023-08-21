require "bundler/gem_tasks"
require "chefstyle"
require "rubocop/rake_task"
require "rspec/core/rake_task"

RuboCop::RakeTask.new(:style) do |task|
  task.options += ["--display-cop-names", "--no-color"]
end

RSpec::Core::RakeTask.new(:test)

RSpec::Core::RakeTask.new do |task|
  #   test_dir = Rake.application.original_dir
  #   task.pattern = "#{test_dir}/*_spec.rb"
  #   task.rspec_opts = [ "-I#{test_dir}", "-I#{test_dir}/source", '-f documentation', '-r ./rspec_config']
  task.verbose = false
end

task default: %i{test style}
