#!/usr/bin/env ruby

require 'xcodeproj'

project_path = ARGV[0] || 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first

puts "📋 Files in build phase:"
puts "=" * 80

file_counts = Hash.new(0)

target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  file_name = file_ref.path || file_ref.display_name || "unknown"
  file_counts[file_name] += 1
end

# Show duplicates first
duplicates = file_counts.select { |_, count| count > 1 }
if duplicates.any?
  puts "\n❌ DUPLICATES FOUND:"
  duplicates.each do |name, count|
    puts "  #{name}: #{count} times"
  end
else
  puts "\n✅ No duplicates found!"
end

puts "\n📊 Total files: #{file_counts.size}"
puts "📊 Total build file entries: #{target.source_build_phase.files.count}"
