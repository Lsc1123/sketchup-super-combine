# frozen_string_literal: true
require 'rbconfig'
files = Dir.glob('{src,tests,tools}/**/*.rb').sort
abort 'No Ruby sources found' if files.empty?
files.each { |file| abort "Syntax error: #{file}" unless system(RbConfig.ruby, '-c', file) }
puts "Ruby syntax: #{files.length} files checked"
