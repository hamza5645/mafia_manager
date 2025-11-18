#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Features/Multiplayer group
features_group = project.main_group['Features']
multiplayer_group = features_group['Multiplayer']

# Add the new file
file_path = 'Features/Multiplayer/MultiplayerRoleRevealView.swift'
file_ref = multiplayer_group.new_file(file_path)

# Add to build phase
target.source_build_phase.add_file_reference(file_ref)

# Save the project
project.save

puts "✅ Added MultiplayerRoleRevealView.swift to project"
