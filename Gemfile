source "https://rubygems.org"

# Specify your gem's dependencies in kitchen-pester.gemspec
gemspec development_group: :test
group :integration do
  gem "berkshelf"
  gem "kitchen-inspec"
  gem "kitchen-azurerm"
  gem "kitchen-chocolatey"
end

group :cookstyle do
  gem "cookstyle"
end

group :test do
  gem "rake"
  gem "minitest", ">= 5.25", "< 7"
  gem "mocha", ">= 2.0", "< 4"
  gem "yard", "~> 0.9"
end
