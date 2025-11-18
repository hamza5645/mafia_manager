#!/usr/bin/env ruby

require 'xcodeproj'

project_path = ARGV[0] || 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first

multiplayer_filenames = [
  'GameAction.swift',
  'GameSession.swift',
  'PhaseTimer.swift',
  'SessionPlayer.swift',
  'RealtimeService.swift',
  'SessionService.swift',
  'MultiplayerGameStore.swift',
  'CreateGameView.swift',
  'GameModeSelectionView.swift',
  'JoinGameView.swift',
  'MultiplayerLobbyView.swift',
  'MultiplayerMenuView.swift',
  'MultiplayerNightView.swift',
  'MultiplayerVotingView.swift'
]

puts "🔍 Searching for multiplayer files in build phase..."

# First pass: Remove ALL instances of multiplayer files from build phase
target.source_build_phase.files.to_a.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  file_name = file_ref.path || file_ref.display_name

  if multiplayer_filenames.include?(file_name)
    puts "  🗑️  Removing: #{file_name}"
    build_file.remove_from_project
  end
end

puts "\n✅ All multiplayer files removed from build phase"

# Second pass: Remove file references from groups
def remove_multiplayer_refs(group, filenames)
  group.files.to_a.each do |file_ref|
    file_name = file_ref.path || file_ref.display_name
    if filenames.include?(file_name)
      puts "  🗑️  Removing group reference: #{file_name}"
      file_ref.remove_from_project
    end
  end

  group.groups.each { |subgroup| remove_multiplayer_refs(subgroup, filenames) }
end

remove_multiplayer_refs(project.main_group, multiplayer_filenames)

project.save
puts "\n✅ Project saved! Now re-run the add script."
