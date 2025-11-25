#!/usr/bin/env ruby
require 'xcodeproj'

# Configuration
PROJECT_PATH = '/Users/hamzaosama/Documents/Developer/SwiftUI/mafia_manager/mafia_manager.xcodeproj'
TARGET_NAME = 'mafia_manager'

# Files to add (passed as arguments)
files_to_add = ARGV

if files_to_add.empty?
  puts "Usage: ruby add_files_to_xcode.rb <file1.swift> [file2.swift] ..."
  exit 1
end

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }

unless target
  puts "Error: Target '#{TARGET_NAME}' not found"
  exit 1
end

files_to_add.each do |file_path|
  unless File.exist?(file_path)
    puts "Warning: File not found: #{file_path}"
    next
  end

  # Determine the group path from the file path
  relative_path = file_path.sub('/Users/hamzaosama/Documents/Developer/SwiftUI/mafia_manager/', '')
  group_path = File.dirname(relative_path)
  file_name = File.basename(file_path)

  # Navigate/create to the appropriate group
  current_group = project.main_group
  group_path.split('/').each do |folder|
    next if folder.empty?
    found_group = current_group.groups.find { |g| g.name == folder || g.path == folder }
    if found_group
      current_group = found_group
    else
      current_group = current_group.new_group(folder, folder)
    end
  end

  # Check if file already exists in project
  existing_ref = current_group.files.find { |f| f.path == file_name }
  if existing_ref
    puts "Skipping (already exists): #{file_name}"
    next
  end

  # Add file reference
  file_ref = current_group.new_file(file_path)

  # Add to target's compile sources
  target.add_file_references([file_ref])

  puts "Added: #{relative_path}"
end

# Save project
project.save
puts "Project saved successfully."
