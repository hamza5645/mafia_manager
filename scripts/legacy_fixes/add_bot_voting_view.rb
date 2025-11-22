#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Voting group
features_group = project.main_group['Features']
voting_group = features_group['Voting']

unless voting_group
  puts "❌ Voting group not found"
  exit 1
end

# Add BotVotingRevealView.swift
file_name = 'BotVotingRevealView.swift'

# Check if file already exists in group
existing = voting_group.files.find { |f| f.path == file_name }

unless existing
  file_ref = voting_group.new_file(file_name)
  target.add_file_references([file_ref])
  puts "✓ Added #{file_name} to Xcode project"
else
  puts "✓ #{file_name} already in project"
end

# Save the project
project.save

puts "✓ Successfully updated Xcode project"
