#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

puts "Fixing group paths and file references..."
puts "=" * 60

# Find the groups that need fixing
groups_to_fix = ['Models', 'Services', 'Store', 'Auth', 'Stats', 'Settings']

project.main_group.recursive_children.each do |item|
  if item.is_a?(Xcodeproj::Project::Object::PBXGroup) && groups_to_fix.include?(item.name)
    puts "\nGroup: #{item.name}"
    puts "  Path: #{item.path}"
    puts "  Source tree: #{item.source_tree}"

    # Check if this group has a path set
    if item.path && !item.path.empty?
      puts "  Group has path set - checking children..."

      # Fix child file references
      item.children.each do |child|
        if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
          child_path = child.path
          puts "    File: #{child_path}"

          # If the child path includes the parent path, make it relative
          if child_path&.start_with?(item.path)
            relative_path = child_path.sub("#{item.path}/", '')
            puts "      Fixing to relative: #{relative_path}"
            child.path = relative_path
          end
        end
      end
    end
  end
end

# Save the project
project.save

puts "\n✅ Groups and paths fixed!"
puts "\nPlease clean and rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
