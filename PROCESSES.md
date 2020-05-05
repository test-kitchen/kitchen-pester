# Release Process for `kitchen-pester`

- [ ] Update local master branch
- [ ] Switch to a new branch: `release_x.xx.x`
- [ ] Delete `Gemfile.lock` & update bundled dependencies:
  - `bundle install`
- [ ] Run tests:
  - `bundle exec rake unit`
  - `bundle exec rake style`
- [ ] Increment verifier version in `./lib/kitchen/verifier/pester_version.rb`
- [ ] Generate changelog & add changelog and new version files
  - Set enviroment variable `$env:CHANGELOG_GITHUB_TOKEN = $your_github_token`
  - `bundle exec rake changelog`
- [ ] Commit changes.
  - `git add ./CHANGELOG.md`
  - `git add ./lib/kitchen/verifier/pester_version.rb`
  - `git commit -m "Version bump & changelog for x.xx.x"`
- [ ] Push release to rubygems:
  - [ ] `bundle exec rake release`
