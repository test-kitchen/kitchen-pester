source "https://rubygems.org"

# Specify your gem's dependencies in kitchen-pester.gemspec
gemspec development_group: :test
group :integration do
  gem "berkshelf"
  gem "kitchen-inspec"
  gem "kitchen-azurerm"
  gem "kitchen-chocolatey"
end

group :debug do
  gem "pry"
  gem "pry-byebug"
  gem "pry-stack_explorer"
end

group :cookstyle do
  gem "cookstyle"
end

group :test do
  gem "rake"
end
