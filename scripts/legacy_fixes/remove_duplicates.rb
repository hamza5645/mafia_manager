#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Track files to remove duplicates for
files_to_dedupe = {
  'InputValidator.swift' => 'Core/Services/InputValidator.swift',
  'KeychainHelper.swift' => 'Core/Services/KeychainHelper.swift',
  'DatabaseService.swift' => 'Core/Services/DatabaseService.swift',
  'RoleRevealView.swift' => 'Features/Assignments/RoleRevealView.swift',
  'PrivacyBlurView.swift' => 'Core/Components/PrivacyBlurView.swift'
}

files_to_dedupe.each do |filename, correct_path|
  puts "\nProcessing #{filename}..."

  # Find all references to this file
  all_refs = []
  project.files.each do |file|
    if file.path&.end_with?(filename) || file.name == filename
      all_refs << file
    end
  end

  puts "  Found #{all_refs.count} references"

  # Remove ALL references from build phases first
  target.source_build_phase.files.each do |build_file|
    if all_refs.include?(build_file.file_ref)
      target.source_build_phase.files.delete(build_file)
    end
  end

  # Remove all file references
  all_refs.each do |ref|
    ref.remove_from_project
  end

  puts "  ✓ Removed all #{all_refs.count} references"

  # Now add ONE correct reference
  # Find the parent group
  path_components = correct_path.split('/')
  filename_only = path_components.pop

  # Navigate to correct group
  current_group = project.main_group
  path_components.each do |component|
    current_group = current_group[component] || current_group.new_group(component)
  end

  # Add file reference
  file_ref = current_group.new_reference(correct_path)
  file_ref.source_tree = 'SOURCE_ROOT'

  # Add to build phase
  target.source_build_phase.add_file_reference(file_ref)

  puts "  ✓ Added single correct reference at #{correct_path}"
end

# Save the project
project.save

puts "\n✅ All duplicates removed and files added correctly!"
