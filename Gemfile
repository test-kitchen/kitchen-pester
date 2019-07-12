source "https://rubygems.org"

# Specify your gem's dependencies in kitchen-pester.gemspec
gemspec

group :integration do
  gem "berkshelf"
  gem "kitchen-inspec"
  gem "kitchen-dokken"
  gem "kitchen-vagrant"
end

group :changelog do
  gem "github_changelog_generator", "1.11.3"
end

group :debug do
  gem "pry"
  gem "pry-byebug"
  gem "pry-stack_explorer"
end

group :chefstyle do
  gem "chefstyle"
end

group :docs do
  gem "yard"
end
