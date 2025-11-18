#!/usr/bin/env ruby

require 'xcodeproj'

project_path = ARGV[0] || 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Remove all file references with duplicated paths
target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref && file_ref.path

  # Check if the path contains duplicate segments
  if file_ref.path.include?('Core/Models/Multiplayer/Core/Models/Multiplayer') ||
     file_ref.path.include?('Core/Services/Multiplayer/Core/Services/Multiplayer') ||
     file_ref.path.include?('Core/Store/Core/Store') ||
     file_ref.path.include?('Features/Multiplayer/Features/Multiplayer')

    puts "🗑️  Removing duplicate: #{file_ref.path}"
    build_file.remove_from_project
  end
end

# Also remove the file references from groups
def remove_duplicates_from_group(group)
  group.files.each do |file_ref|
    if file_ref.path && (
        file_ref.path.include?('Core/Models/Multiplayer/Core/Models/Multiplayer') ||
        file_ref.path.include?('Core/Services/Multiplayer/Core/Services/Multiplayer') ||
        file_ref.path.include?('Core/Store/Core/Store') ||
        file_ref.path.include?('Features/Multiplayer/Features/Multiplayer')
      )
      puts "🗑️  Removing reference: #{file_ref.path}"
      file_ref.remove_from_project
    end
  end

  group.groups.each { |subgroup| remove_duplicates_from_group(subgroup) }
end

remove_duplicates_from_group(project.main_group)

# Now add the files correctly
def get_or_create_group(parent_group, group_name)
  group = parent_group.groups.find { |g| g.name == group_name || g.path == group_name }
  if group.nil?
    group = parent_group.new_group(group_name, group_name)
  end
  group
end

multiplayer_files = [
  'Core/Models/Multiplayer/GameAction.swift',
  'Core/Models/Multiplayer/GameSession.swift',
  'Core/Models/Multiplayer/PhaseTimer.swift',
  'Core/Models/Multiplayer/SessionPlayer.swift',
  'Core/Services/Multiplayer/RealtimeService.swift',
  'Core/Services/Multiplayer/SessionService.swift',
  'Core/Store/MultiplayerGameStore.swift',
  'Features/Multiplayer/CreateGameView.swift',
  'Features/Multiplayer/GameModeSelectionView.swift',
  'Features/Multiplayer/JoinGameView.swift',
  'Features/Multiplayer/MultiplayerLobbyView.swift',
  'Features/Multiplayer/MultiplayerMenuView.swift',
  'Features/Multiplayer/MultiplayerNightView.swift',
  'Features/Multiplayer/MultiplayerVotingView.swift'
]

multiplayer_files.each do |file_path|
  next unless File.exist?(file_path)

  # Parse the path to create the group hierarchy
  path_parts = file_path.split('/')
  file_name = path_parts.last

  # Navigate/create the group hierarchy
  current_group = project.main_group
  path_parts[0..-2].each do |part|
    current_group = get_or_create_group(current_group, part)
  end

  # Check if file already exists in the group
  existing_file = current_group.files.find { |f| f.path == file_name }

  unless existing_file
    # Add the file reference with the correct path
    file_ref = current_group.new_reference(file_name)
    file_ref.source_tree = '<group>'

    # Add to target if it's a Swift file
    if file_name.end_with?('.swift')
      target.add_file_references([file_ref])
      puts "✅ Added correctly: #{file_path}"
    end
  else
    puts "⏭️  Already exists: #{file_path}"
  end
end

project.save

puts "\n🎉 Successfully fixed multiplayer file paths!"
