#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Files to check (we want to keep the full path version)
files_to_deduplicate = [
  'AuthService.swift',
  'DatabaseService.swift',
  'SupabaseConfig.swift',
  'SupabaseService.swift',
  'AuthStore.swift',
  'LoginView.swift',
  'ProfileView.swift',
  'SignupView.swift',
  'PlayerStatsView.swift',
  'CustomRolesView.swift',
  'SettingsView.swift'
]

removed_count = 0

puts "Removing duplicate file references..."
puts "=" * 60

target.source_build_phase.files.to_a.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  file_name = File.basename(file_ref.path)
  file_path = file_ref.path

  # If this is a relative path (not starting with Core/ or Features/)
  # and it's in our list of duplicates, remove it
  if files_to_deduplicate.include?(file_name) &&
     !file_path.start_with?('Core/') &&
     !file_path.start_with?('Features/')

    puts "Removing relative path reference: #{file_path} (parent: #{file_ref.parent ? file_ref.parent.path : 'root'})"
    build_file.remove_from_project
    removed_count += 1
  end
end

# Save the project
project.save

puts "\n✅ Cleanup complete!"
puts "Removed #{removed_count} duplicate references"
puts "\nPlease clean and rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
