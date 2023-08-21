source "https://rubygems.org"

gemspec

group :integration do
  gem "berkshelf"
  gem "kitchen-inspec"
  gem "kitchen-azurerm"
  gem "kitchen-chocolatey"
end

group :debug do
  gem "pry", "~>0.13.1"
  gem "pry-byebug", "~>3.9.0"
  gem "pry-stack_explorer"
end

group :development do
  gem "rake", ">= 11.0"
  #   gem "minitest"#, "~> 5.3", "< 5.16" # Commented out as these tests are not run
  #   gem "mocha"#, "~> 1.1"
end

group :chefstyle do
  gem "chefstyle"
end

group :docs do
  gem "yard"
end
