#!/usr/bin/env ruby

require 'xcodeproj'

project_path = ARGV[0] || 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Track which files we've seen
seen_files = Set.new

# Remove duplicates from the compile sources build phase
target.source_build_phase.files.to_a.reverse.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  file_path = file_ref.real_path.to_s rescue file_ref.path.to_s

  if seen_files.include?(file_path)
    puts "🗑️  Removing duplicate build file: #{file_path}"
    build_file.remove_from_project
  else
    seen_files.add(file_path)
  end
end

project.save

puts "\n✅ Removed all duplicate file references from target!"
