#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Core/Services group
services_group = project.main_group['Core']['Services']

# Remove existing bad references
files_to_remove = ['InputValidator.swift', 'KeychainHelper.swift']
files_to_remove.each do |filename|
  existing = services_group.files.find { |f| f.path == filename }
  if existing
    # Remove from build phase
    target.source_build_phase.files.each do |build_file|
      if build_file.file_ref == existing
        target.source_build_phase.files.delete(build_file)
        puts "✓ Removed bad reference for #{filename} from build phase"
      end
    end
    # Remove from group
    existing.remove_from_project
    puts "✓ Removed bad file reference for #{filename}"
  end
end

# Files to add with correct paths
files_to_add = {
  'InputValidator.swift' => 'Core/Services/InputValidator.swift',
  'KeychainHelper.swift' => 'Core/Services/KeychainHelper.swift'
}

files_to_add.each do |filename, relative_path|
  # Create file reference with correct path
  file_ref = services_group.new_reference(relative_path)
  file_ref.name = filename

  # Add to build phase
  target.source_build_phase.add_file_reference(file_ref)

  puts "✓ Added #{filename} correctly"
end

# Save the project
project.save

puts "\n✅ Security files fixed in Xcode project successfully!"
