#!/usr/bin/env ruby

require "xcodeproj"

repository_root = File.expand_path("..", __dir__)
project_path = File.join(repository_root, "BikeGoGo", "BikeGoGo.xcodeproj")
project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |target| target.name == "BikeGoGoWatch" }
  puts "BikeGoGoWatch target already exists"
  exit 0
end

watch_target = project.new_target(
  :application,
  "BikeGoGoWatch",
  :watchos,
  "10.0"
)

watch_group = project.main_group.new_group(
  "BikeGoGoWatch",
  "../Apps/watchOS/BikeGoGoWatch"
)

source_paths = [
  "BikeGoGoWatchApp.swift",
  "WatchRideView.swift",
  "Services/WatchSessionBridge.swift",
  "Services/WatchWorkoutManager.swift"
]
source_references = source_paths.map { |path| watch_group.new_file(path) }
watch_target.add_file_references(source_references)

support_group = watch_group.new_group("Support", "Support")
entitlements_reference = support_group.new_file("BikeGoGoWatch.entitlements")
support_group.new_file("Info.plist")

health_kit = project.frameworks_group.new_file(
  "System/Library/Frameworks/HealthKit.framework",
  :sdk_root
)
watch_connectivity = project.frameworks_group.new_file(
  "System/Library/Frameworks/WatchConnectivity.framework",
  :sdk_root
)
watch_target.frameworks_build_phase.add_file_reference(health_kit)
watch_target.frameworks_build_phase.add_file_reference(watch_connectivity)

watch_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  settings["CODE_SIGN_ENTITLEMENTS"] = entitlements_reference.real_path.relative_path_from(
    project.path.dirname
  ).to_s
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CURRENT_PROJECT_VERSION"] = "3"
  settings["DEVELOPMENT_TEAM"] = "FR9RTRV9BC"
  settings["ENABLE_PREVIEWS"] = "YES"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["INFOPLIST_FILE"] = "../Apps/watchOS/BikeGoGoWatch/Support/Info.plist"
  settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks"
  settings["MARKETING_VERSION"] = "1.0"
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.sssnto.BikeGoGo.watchkitapp"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["SDKROOT"] = "watchos"
  settings["SKIP_INSTALL"] = "YES"
  settings["SWIFT_VERSION"] = "5.0"
  settings["TARGETED_DEVICE_FAMILY"] = "4"
  settings["WATCHOS_DEPLOYMENT_TARGET"] = "10.0"
end

ios_target = project.targets.find { |target| target.name == "BikeGoGo" }
ios_target.add_dependency(watch_target)

embed_phase = ios_target.new_copy_files_build_phase("Embed Watch Content")
embed_phase.dst_path = "$(CONTENTS_FOLDER_PATH)/Watch"
embed_phase.dst_subfolder_spec = "16"
embed_phase.add_file_reference(watch_target.product_reference)

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch_target)
scheme.set_launch_target(watch_target)
scheme.save_as(project_path, "BikeGoGoWatch", true)

puts "Created BikeGoGoWatch target and shared scheme"
