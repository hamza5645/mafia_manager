#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

puts "Build files in project:"
puts "=" * 60

target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  puts "#{file_ref.path} (parent: #{file_ref.parent ? file_ref.parent.path : 'root'})"
end
