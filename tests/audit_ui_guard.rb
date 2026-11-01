# frozen_string_literal: true
# Isolated Ruby characterization of the real main.rb busy guard. No SketchUp
# entities are emulated and no claim about native event delivery is made.
abort 'Run this probe in standalone Ruby, never in SketchUp' if defined?(Sketchup)
require 'json'
require 'fileutils'
module Geom
  class Transformation; end
end
module Sketchup
  def self.set_status_text(_text); end
end
def file_loaded?(_path)
  true # Skip registration of menus/toolbars; exercise only the real run method.
end
$LOADED_FEATURES << 'sketchup.rb'
require_relative '../src/lsc_super_combine/main'

module LSC::SuperCombine::Engine
  def self.combine
    @audit_calls=(@audit_calls || 0)+1
    if @audit_calls==1
      LSC::SuperCombine.run # Refused while the original call is busy.
      @audit_busy_after_rejected_call=LSC::SuperCombine.instance_variable_get(:@busy)
      LSC::SuperCombine.run # Should also be refused while the original runs.
    end
    [nil,{inputs: 1,repaired_faces: 0}]
  end
  def self.audit_result
    {engine_calls: @audit_calls,busy_after_rejected_call: @audit_busy_after_rejected_call}
  end
end

LSC::SuperCombine.run
result=LSC::SuperCombine::Engine.audit_result
report={scope: 'Real run method with a stubbed engine; native callbacks not tested',
        ruby: RUBY_DESCRIPTION,expected_engine_calls: 1,actual: result,
        pass: result[:engine_calls]==1 && result[:busy_after_rejected_call]==true}
output=ARGV.first || File.expand_path('../test-results/audit-ui-guard.json',__dir__)
FileUtils.mkdir_p(File.dirname(output))
File.write(output,JSON.pretty_generate(report)+"\n")
puts JSON.pretty_generate(report)
exit(report[:pass] ? 0 : 1)
