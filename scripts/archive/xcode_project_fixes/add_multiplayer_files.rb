#!/usr/bin/env ruby

require 'xcodeproj'

project_path = ARGV[0] || 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Define the files to add
multiplayer_files = [
  # Models
  'Core/Models/Multiplayer/GameAction.swift',
  'Core/Models/Multiplayer/GameSession.swift',
  'Core/Models/Multiplayer/PhaseTimer.swift',
  'Core/Models/Multiplayer/SessionPlayer.swift',

  # Services
  'Core/Services/Multiplayer/RealtimeService.swift',
  'Core/Services/Multiplayer/SessionService.swift',

  # Store
  'Core/Store/MultiplayerGameStore.swift',

  # Views
  'Features/Multiplayer/CreateGameView.swift',
  'Features/Multiplayer/GameModeSelectionView.swift',
  'Features/Multiplayer/JoinGameView.swift',
  'Features/Multiplayer/MultiplayerLobbyView.swift',
  'Features/Multiplayer/MultiplayerMenuView.swift',
  'Features/Multiplayer/MultiplayerNightView.swift',
  'Features/Multiplayer/MultiplayerVotingView.swift'
]

def get_or_create_group(parent_group, group_name)
  group = parent_group.groups.find { |g| g.name == group_name || g.path == group_name }
  if group.nil?
    group = parent_group.new_group(group_name, group_name)
  end
  group
end

# Add each file
multiplayer_files.each do |file_path|
  next unless File.exist?(file_path)

  # Parse the path to create the group hierarchy
  path_parts = file_path.split('/')
  file_name = path_parts.pop

  # Navigate/create the group hierarchy
  current_group = project.main_group
  path_parts.each do |part|
    current_group = get_or_create_group(current_group, part)
  end

  # Check if file already exists in the group
  existing_file = current_group.files.find { |f| f.path == file_name }

  unless existing_file
    # Add the file reference (use just filename, not full path)
    file_ref = current_group.new_reference(file_name)
    file_ref.source_tree = '<group>'

    # Add to target if it's a Swift file
    if file_name.end_with?('.swift')
      target.add_file_references([file_ref])
      puts "✅ Added: #{file_path}"
    end
  else
    puts "⏭️  Already exists: #{file_path}"
  end
end

# Save the project
project.save

puts "\n🎉 Successfully added multiplayer files to Xcode project!"
