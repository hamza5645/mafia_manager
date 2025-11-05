#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Files that should be in Services (not Models)
service_files = [
  'AuthService.swift',
  'DatabaseService.swift',
  'SupabaseConfig.swift',
  'SupabaseService.swift'
]

# Remove duplicate file references
puts "Removing duplicate file references..."
target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  file_name = file_ref.path

  # Remove files from Models that should be in Services
  if file_ref.parent && file_ref.parent.path == 'Core/Models' && service_files.include?(file_name)
    puts "Removing duplicate from Models: #{file_name}"
    build_file.remove_from_project
    file_ref.remove_from_project
  end
end

# Remove duplicate build file entries
puts "\nRemoving duplicate build phase entries..."
files_seen = {}
duplicates_to_remove = []

target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  key = file_ref.real_path.to_s

  if files_seen[key]
    puts "Found duplicate build entry for: #{file_ref.path}"
    duplicates_to_remove << build_file
  else
    files_seen[key] = true
  end
end

duplicates_to_remove.each do |build_file|
  build_file.remove_from_project
end

# Save the project
project.save

puts "\n✅ Duplicates removed successfully!"
puts "Total duplicates removed: #{duplicates_to_remove.count}"
puts "\nPlease clean and rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
