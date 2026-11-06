#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
Dir.chdir(root)
project = Xcodeproj::Project.new('GoveeController.xcodeproj')
app = project.new_target(:application, 'GoveeController', :osx, '26.0')
controls = project.new_target(:app_extension, 'GoveeControls', :osx, '26.0')
groups = {}
Dir['Sources/**/*.swift'].sort.each do |path|
  folder = File.dirname(path)
  group = groups[folder] ||= project.main_group.new_group(folder, folder)
  file = group.new_file(File.basename(path))
  case folder
  when 'Sources/App' then app.add_file_references([file])
  when 'Sources/Controls' then controls.add_file_references([file])
  else [app, controls].each { |target| target.add_file_references([file]) }
  end
end

app.add_dependency(controls)
assets = project.main_group.new_file('Resources/Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(controls.product_reference).settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}

[app, controls].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => target == app ? 'com.henryyang.GoveeController' : 'com.henryyang.GoveeController.Controls',
      'PRODUCT_NAME' => target == app ? 'Govee Controller' : 'GoveeControls',
      'SWIFT_VERSION' => '6.0',
      'MACOSX_DEPLOYMENT_TARGET' => '26.0',
      'SDKROOT' => 'macosx',
      'DEVELOPMENT_TEAM' => '8TB23NN2NM',
      'CODE_SIGN_STYLE' => 'Manual',
      'CODE_SIGN_IDENTITY' => 'Apple Development',
      'CODE_SIGN_ENTITLEMENTS' => target == app ? 'Config/App.entitlements' : 'Config/Controls.entitlements',
      'INFOPLIST_FILE' => target == app ? 'Config/App-Info.plist' : 'Config/Controls-Info.plist',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'MARKETING_VERSION' => '1.0.1',
      'CURRENT_PROJECT_VERSION' => '2',
      'ENABLE_HARDENED_RUNTIME' => 'YES',
      'SWIFT_EMIT_LOC_STRINGS' => 'YES',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks'],
      'COMBINE_HIDPI_IMAGES' => 'YES'
    })
    config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' if target == controls
    config.build_settings['SKIP_INSTALL'] = target == app ? 'NO' : 'YES'
    if target == app
      config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
      config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
    end
  end
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'GoveeController', true)
project.save
puts 'Generated GoveeController.xcodeproj'
