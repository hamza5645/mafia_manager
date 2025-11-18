#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

puts "Fixing file paths..."
puts "=" * 60

target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  path = file_ref.path

  # Fix doubled paths
  if path =~ /^(Core\/Models)\/\1/ ||
     path =~ /^(Core\/Services)\/\1/ ||
     path =~ /^(Core\/Store)\/\1/ ||
     path =~ /^(Features\/Auth)\/\1/ ||
     path =~ /^(Features\/Stats)\/\1/ ||
     path =~ /^(Features\/Settings)\/\1/

    # Extract the correct path (remove the prefix duplication)
    correct_path = path.sub(/^[^\/]+\/[^\/]+\//, '')
    puts "Fixing: #{path} -> #{correct_path}"
    file_ref.path = correct_path
  end
end

# Save the project
project.save

puts "\n✅ File paths fixed!"
puts "\nPlease clean and rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
