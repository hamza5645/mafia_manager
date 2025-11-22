#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the file reference
target = project.targets.first
features_group = project.main_group['Features']
multiplayer_group = features_group['Multiplayer']

# Remove the incorrectly added file
multiplayer_group.files.each do |file_ref|
  if file_ref.path&.include?('MultiplayerRoleRevealView.swift')
    puts "Removing: #{file_ref.path}"
    file_ref.remove_from_project
  end
end

# Add it correctly
file_ref = multiplayer_group.new_reference('MultiplayerRoleRevealView.swift')
target.source_build_phase.add_file_reference(file_ref)

# Save the project
project.save

puts "✅ Fixed MultiplayerRoleRevealView.swift path in project"
