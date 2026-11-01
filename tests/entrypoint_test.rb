# frozen_string_literal: true
abort 'Standalone Ruby only' if defined?(Sketchup)
require 'minitest/autorun'
module Geom
  class Transformation; end
end
module Sketchup
  def self.set_status_text(_text); end
end
module UI
  def self.messagebox(_text); end
end
def file_loaded?(_path); true; end
$LOADED_FEATURES << 'sketchup.rb'
require_relative '../src/lsc_super_combine/main'

class EntrypointTest < Minitest::Test
  Plugin = LSC::SuperCombine
  Engine = Plugin::Engine
  def setup
    Plugin.instance_variable_set(:@busy,false)
    @original=Engine.method(:combine)
  end
  def teardown
    Engine.define_singleton_method(:combine,@original)
    Plugin.instance_variable_set(:@busy,false)
  end
  def result
    [:group,{inputs:1,repaired_faces:0}]
  end
  def test_rejected_reentry_keeps_outer_lock
    calls=0
    test=self
    Engine.define_singleton_method(:combine) do
      calls+=1
      assert_busy=Plugin.instance_variable_get(:@busy)
      raise 'missing outer lock' unless assert_busy
      2.times do
        raise 'reentrant run returned a group' unless Plugin.run.nil?
        raise 'reentrant run cleared lock' unless Plugin.instance_variable_get(:@busy)
      end
      test.result
    end
    assert_equal :group,Plugin.run
    assert_equal 1,calls
    refute Plugin.instance_variable_get(:@busy)
  end
  def test_failure_unlocks_and_next_run_succeeds
    Engine.define_singleton_method(:combine) { raise Plugin::CombineError,'expected failure' }
    assert_nil Plugin.run
    refute Plugin.instance_variable_get(:@busy)
    value=result
    Engine.define_singleton_method(:combine) { value }
    assert_equal :group,Plugin.run
  end
  def test_unexpected_failure_also_unlocks
    Engine.define_singleton_method(:combine) { raise ArgumentError,'unexpected failure' }
    assert_raises(ArgumentError) { Plugin.run }
    refute Plugin.instance_variable_get(:@busy)
  end
end
