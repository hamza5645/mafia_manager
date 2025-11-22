#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Features and Core/Models groups
features_group = project.main_group['Features']
models_group = project.main_group['Core']['Models']

# Create Voting group if it doesn't exist
voting_group = features_group['Voting'] || features_group.new_group('Voting', 'Features/Voting')

# Add voting view files
voting_files = [
  'Features/Voting/VotingView.swift',
  'Features/Voting/VoteResultsView.swift'
]

voting_files.each do |file_path|
  file_name = File.basename(file_path)

  # Check if file already exists in group
  existing = voting_group.files.find { |f| f.path == file_name }
  next if existing

  # Add file reference
  file_ref = voting_group.new_file(file_path)

  # Add to target's sources build phase
  target.add_file_references([file_ref])
end

# Add VotingSession.swift to Models group
model_file = 'Core/Models/VotingSession.swift'
model_name = File.basename(model_file)

existing_model = models_group.files.find { |f| f.path == model_name }
unless existing_model
  model_ref = models_group.new_file(model_file)
  target.add_file_references([model_ref])
end

# Save the project
project.save

puts "✓ Successfully added voting files to Xcode project"
