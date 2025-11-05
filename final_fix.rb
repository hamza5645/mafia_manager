#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

puts "Final comprehensive fix..."
puts "=" * 60

# List of files to fix with their correct paths relative to project root
files_to_fix = {
  'UserProfile.swift' => 'Core/Models/UserProfile.swift',
  'PlayerStats.swift' => 'Core/Models/PlayerStats.swift',
  'CustomRoleConfig.swift' => 'Core/Models/CustomRoleConfig.swift',
  'AuthService.swift' => 'Core/Services/AuthService.swift',
  'DatabaseService.swift' => 'Core/Services/DatabaseService.swift',
  'SupabaseConfig.swift' => 'Core/Services/SupabaseConfig.swift',
  'SupabaseService.swift' => 'Core/Services/SupabaseService.swift',
  'AuthStore.swift' => 'Core/Store/AuthStore.swift',
  'LoginView.swift' => 'Features/Auth/LoginView.swift',
  'ProfileView.swift' => 'Features/Auth/ProfileView.swift',
  'SignupView.swift' => 'Features/Auth/SignupView.swift',
  'PlayerStatsView.swift' => 'Features/Stats/PlayerStatsView.swift',
  'CustomRolesView.swift' => 'Features/Stats/CustomRolesView.swift',
  'SettingsView.swift' => 'Features/Settings/SettingsView.swift'
}

# Step 1: Find and fix file references
project.files.each do |file_ref|
  file_name = File.basename(file_ref.path) if file_ref.path

  if file_name && files_to_fix.key?(file_name)
    puts "Fixing file reference: #{file_name}"
    puts "  Current path: #{file_ref.path}"
    puts "  Current source tree: #{file_ref.source_tree}"

    # Set the file to use project-relative path with SOURCE_ROOT
    file_ref.path = files_to_fix[file_name]
    file_ref.source_tree = 'SOURCE_ROOT'

    puts "  New path: #{file_ref.path}"
    puts "  New source tree: #{file_ref.source_tree}"
  end
end

# Save the project
project.save

puts "\n✅ Project fixed with SOURCE_ROOT paths!"
puts "\nPlease clean and rebuild:"
puts "1. Clean build folder: Cmd+Shift+K"
puts "2. Build: Cmd+B"
