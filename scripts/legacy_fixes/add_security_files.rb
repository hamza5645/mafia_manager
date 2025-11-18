#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Core/Services group
services_group = project.main_group['Core']['Services']

# Files to add
files_to_add = [
  'Core/Services/KeychainHelper.swift',
  'Core/Services/InputValidator.swift'
]

files_to_add.each do |file_path|
  # Check if file already exists in project
  existing = services_group.files.find { |f| f.path == File.basename(file_path) }

  if existing
    puts "✓ #{file_path} already in project"
  else
    # Add the file to the group
    file_ref = services_group.new_file(file_path)

    # Add to build phase
    target.source_build_phase.add_file_reference(file_ref)

    puts "✓ Added #{file_path} to project"
  end
end

# Save the project
project.save

puts "\n✅ Security files added to Xcode project successfully!"
