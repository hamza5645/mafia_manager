#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'mafia_manager.xcodeproj'
project = Xcodeproj::Project.open(project_path)

files_to_fix = {
  'NightWakeUpView.swift' => 'Features/Night/NightWakeUpView.swift'
}

project.files.each do |file_ref|
  file_name = File.basename(file_ref.path) if file_ref.path

  if file_name && files_to_fix.key?(file_name)
    puts "Fixing: #{file_name}"
    file_ref.path = files_to_fix[file_name]
    file_ref.source_tree = 'SOURCE_ROOT'
  end
end

project.save
puts "✅ Project updated!"
