#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Files to add with their groups
files_to_add = {
  'Core/Models' => [
    'Core/Models/UserProfile.swift',
    'Core/Models/PlayerStats.swift',
    'Core/Models/CustomRoleConfig.swift'
  ],
  'Core/Services' => [
    'Core/Services/AuthService.swift',
    'Core/Services/DatabaseService.swift',
    'Core/Services/SupabaseConfig.swift',
    'Core/Services/SupabaseService.swift'
  ],
  'Core/Store' => [
    'Core/Store/AuthStore.swift'
  ],
  'Features/Auth' => [
    'Features/Auth/LoginView.swift',
    'Features/Auth/ProfileView.swift',
    'Features/Auth/SignupView.swift'
  ],
  'Features/Stats' => [
    'Features/Stats/PlayerStatsView.swift',
    'Features/Stats/CustomRolesView.swift'
  ],
  'Features/Settings' => [
    'Features/Settings/SettingsView.swift'
  ]
}

# Function to find or create group
def find_or_create_group(project, path)
  parts = path.split('/')
  current_group = project.main_group

  parts.each do |part|
    next_group = current_group[part]
    if next_group.nil?
      next_group = current_group.new_group(part, part)
    end
    current_group = next_group
  end

  current_group
end

# Add files to project
files_to_add.each do |group_path, files|
  group = find_or_create_group(project, group_path)

  files.each do |file_path|
    # Check if file already exists in project
    existing_file = project.files.find { |f| f.path == file_path }

    unless existing_file
      # Add file reference to group
      file_ref = group.new_file(file_path)

      # Add file to target's build phase
      if file_path.end_with?('.swift')
        target.source_build_phase.add_file_reference(file_ref)
      end

      puts "Added: #{file_path}"
    else
      puts "Already exists: #{file_path}"
    end
  end
end

# Save the project
project.save

puts "\n✅ Project updated successfully!"
puts "Please clean and rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
