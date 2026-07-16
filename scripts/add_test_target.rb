#!/usr/bin/env ruby
# Add (or update) the SnipKeyTests unit-test target, hosted by the SnipKey app.
#
# - Creates the target if missing (TEST_HOST = the SnipKey app, so @testable import works).
# - Registers every SnipKeyTests/*.swift file that isn't in the target yet (idempotent —
#   re-run after adding a new test file, mirroring scripts/add_v2_files.py for V2 sources).
# - Creates/refreshes a shared "SnipKeyTests" scheme so `xcodebuild test` finds it.
#
# Usage: ruby scripts/add_test_target.rb

require 'xcodeproj'

project_path = File.expand_path('../SnipKey.xcodeproj', __dir__)
tests_dir = File.expand_path('../SnipKeyTests', __dir__)

project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'SnipKey' }
abort 'ERROR: SnipKey app target not found' unless app_target

test_target = project.targets.find { |t| t.name == 'SnipKeyTests' }
created = false

if test_target.nil?
  test_target = project.new_target(:unit_test_bundle, 'SnipKeyTests', :ios, '17.0')
  test_target.add_dependency(app_target)
  created = true
end

# (Re)apply build settings so re-runs repair a broken target definition.
test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/SnipKey.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SnipKey'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'jrtv-projects.SnipKey.SnipKeyTests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
end

group = project.main_group.find_subpath('SnipKeyTests', true)
group.source_tree = '<group>'
group.path = 'SnipKeyTests' if group.path.nil?

existing = test_target.source_build_phase.files_references.map(&:display_name)
added = []
Dir.glob(File.join(tests_dir, '*.swift')).sort.each do |file|
  name = File.basename(file)
  next if existing.include?(name)
  ref = group.files.find { |f| f.display_name == name } || group.new_reference(name)
  test_target.add_file_references([ref])
  added << name
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, 'SnipKeyTests', true)

puts(created ? 'Created SnipKeyTests target.' : 'SnipKeyTests target already exists.')
puts added.empty? ? 'No new test files.' : "Added test files:\n  " + added.join("\n  ")
puts 'Shared scheme SnipKeyTests written.'
