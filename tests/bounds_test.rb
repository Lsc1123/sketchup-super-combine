# frozen_string_literal: true
abort 'Standalone Ruby only' if defined?(Sketchup)
require 'minitest/autorun'
module Geom
  class Transformation; end
end
require_relative '../src/lsc_super_combine/engine'

class BoundsTest < Minitest::Test
  Engine=LSC::SuperCombine::Engine
  Box=Struct.new(:min,:max)
  Group=Struct.new(:bounds)
  def group(low,high)
    Group.new(Box.new(low,high))
  end
  def test_union_extents_include_every_operand
    inputs=[group([0,0,0],[34,10,10]),group([60,0,0],[62,2,2])]
    assert_equal [[0,0,0],[62,10,10]],Engine.combined_bounds(inputs)
  end
  def test_missing_third_solid_is_rejected
    expected=[[0,0,0],[62,10,10]]
    assert_raises(LSC::SuperCombine::CombineError) { Engine.verify_bounds!(group([0,0,0],[34,10,10]),expected) }
  end
  def test_spurious_geometry_is_rejected
    assert_raises(LSC::SuperCombine::CombineError) do
      Engine.verify_bounds!(group([-5,0,0],[62,10,10]),[[0,0,0],[62,10,10]])
    end
  end
  def test_correct_bounds_accept_small_roundoff
    assert_nil Engine.verify_bounds!(group([1e8,0,0],[1e8+10+1e-7,10,10]),[[1e8,0,0],[1e8+10,10,10]])
  end
  def test_nonfinite_bounds_are_rejected
    assert_raises(LSC::SuperCombine::CombineError) do
      Engine.verify_bounds!(group([Float::NAN,0,0],[10,10,10]),[[0,0,0],[10,10,10]])
    end
  end
end
