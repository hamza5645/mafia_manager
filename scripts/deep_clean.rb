#!/usr/bin/env ruby

require 'xcodeproj'

project_path = ARGV[0] || 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first

puts "🔍 Deep cleaning all multiplayer file references..."

# Remove ALL build files that contain "Multiplayer" in their path
removed_count = 0
target.source_build_phase.files.to_a.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  file_path = file_ref.real_path.to_s rescue file_ref.path.to_s

  # Check if this is a multiplayer file by looking for keywords in path
  if file_path.include?('Multiplayer') ||
     file_path.include?('GameAction') ||
     file_path.include?('GameSession') ||
     file_path.include?('PhaseTimer') ||
     file_path.include?('SessionPlayer') ||
     file_path.include?('RealtimeService') ||
     file_path.include?('SessionService') ||
     file_path.include?('MultiplayerGameStore') ||
     file_path.include?('CreateGameView') ||
     file_path.include?('GameModeSelectionView') ||
     file_path.include?('JoinGameView') ||
     file_path.include?('MultiplayerLobbyView') ||
     file_path.include?('MultiplayerMenuView') ||
     file_path.include?('MultiplayerNightView') ||
     file_path.include?('MultiplayerVotingView')

    puts "  🗑️  Removing build file: #{file_path}"
    build_file.remove_from_project
    removed_count += 1
  end
end

puts "\n✅ Removed #{removed_count} build file references"

# Remove ALL file references from groups
def deep_clean_groups(group, removed_refs)
  group.files.to_a.each do |file_ref|
    file_path = file_ref.real_path.to_s rescue file_ref.path.to_s

    if file_path.include?('Multiplayer') ||
       file_path.include?('GameAction') ||
       file_path.include?('GameSession') ||
       file_path.include?('PhaseTimer') ||
       file_path.include?('SessionPlayer') ||
       file_path.include?('RealtimeService') ||
       file_path.include?('SessionService') ||
       file_path.include?('MultiplayerGameStore') ||
       file_path.include?('CreateGameView') ||
       file_path.include?('GameModeSelectionView') ||
       file_path.include?('JoinGameView') ||
       file_path.include?('MultiplayerLobbyView') ||
       file_path.include?('MultiplayerMenuView') ||
       file_path.include?('MultiplayerNightView') ||
       file_path.include?('MultiplayerVotingView')

      puts "  🗑️  Removing group reference: #{file_path}"
      file_ref.remove_from_project
      removed_refs[:count] += 1
    end
  end

  group.groups.each { |subgroup| deep_clean_groups(subgroup, removed_refs) }
end

removed_refs = { count: 0 }
deep_clean_groups(project.main_group, removed_refs)

puts "\n✅ Removed #{removed_refs[:count]} group references"

project.save

puts "\n🎉 Deep clean complete!"
