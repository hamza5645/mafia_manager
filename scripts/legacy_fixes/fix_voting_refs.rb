#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Features and Core/Models groups
features_group = project.main_group['Features']
models_group = project.main_group['Core']['Models']

# Remove existing voting files if present
voting_group = features_group['Voting']
if voting_group
  voting_group.files.each do |file|
    if file.path.include?('VotingView.swift') || file.path.include?('VoteResultsView.swift')
      file.remove_from_project
    end
  end
else
  voting_group = features_group.new_group('Voting', 'Features/Voting')
end

# Remove existing VotingSession.swift from Models
models_group.files.each do |file|
  if file.path.include?('VotingSession.swift')
    file.remove_from_project
  end
end

# Add voting view files with correct paths (relative to group)
voting_files = [
  { name: 'VotingView.swift', path: 'VotingView.swift' },
  { name: 'VoteResultsView.swift', path: 'VoteResultsView.swift' }
]

voting_files.each do |file_info|
  file_ref = voting_group.new_file(file_info[:path])
  target.add_file_references([file_ref])
end

# Add VotingSession.swift to Models group (relative to group)
model_ref = models_group.new_file('VotingSession.swift')
target.add_file_references([model_ref])

# Save the project
project.save

puts "✓ Successfully fixed voting file references in Xcode project"
