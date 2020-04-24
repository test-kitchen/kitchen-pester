source "https://rubygems.org"

# Specify your gem's dependencies in kitchen-pester.gemspec
gemspec

group :integration do
  gem "berkshelf"
  gem "kitchen-inspec"
  gem "kitchen-azurerm"
  gem "kitchen-chocolatey"
end

group :changelog do
  gem "github_changelog_generator", "1.15.0"
end

group :debug do
  gem "pry", "~>0.12.0"
  gem "pry-byebug", "~3.8.0"
  gem "pry-stack_explorer"
end

group :chefstyle do
  gem "chefstyle"
end

group :docs do
  gem "yard"
end
