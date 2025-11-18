#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Files to add with their groups
files_to_add = {
  'Features/Assignments' => [
    'Features/Assignments/RoleRevealView.swift'
  ],
  'Core/Components' => [
    'Core/Components/PrivacyBlurView.swift'
  ],
  'Features/Night' => [
    'Features/Night/NightWakeUpView.swift'
  ]
}

# Function to find or create group
def find_or_create_group(project, path)
  parts = path.split('/')
  current_group = project.main_group

  parts.each do |part|
    next_group = current_group[part]
    if next_group.nil?
      next_group = current_group.new_group(part, part)
    end
    current_group = next_group
  end

  current_group
end

# Add each file
files_to_add.each do |group_path, files|
  group = find_or_create_group(project, group_path)

  files.each do |file_path|
    # Check if file already exists in project
    existing_file = project.files.find { |f| f.path == File.basename(file_path) }

    if existing_file
      puts "Already exists: #{file_path}"
    else
      # Add file to group - use the full path from project root
      file_ref = group.new_file(File.join(Dir.pwd, file_path))

      # Add to build phase
      target.source_build_phase.add_file_reference(file_ref)

      puts "Added: #{file_path}"
    end
  end
end

# Save the project
project.save

puts "\n✅ Project updated successfully!"
puts "Please clean and rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
