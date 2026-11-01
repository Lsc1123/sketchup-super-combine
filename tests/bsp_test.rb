# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/geom'
module LSC
  module SuperCombine
    class CombineError < StandardError; end
  end
end
require_relative '../src/lsc_super_combine/bsp'

class BSPTest < Minitest::Test
  BSP = LSC::SuperCombine::BSP
  def cube(x=0,y=0,z=0,size=10,source=:material)
    # Six independently defined outward-oriented faces.
    points = [[x,y,z],[x+size,y,z],[x+size,y+size,z],[x,y+size,z],
              [x,y,z+size],[x+size,y,z+size],[x+size,y+size,z+size],[x,y+size,z+size]]
    [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].map do |indices|
      BSP::Polygon.new(indices.map { |i| Geom::Point3d.new(points[i]) }, source)
    end
  end
  def hollow
    inner=cube(3,3,3,4,:inner)
    inner.each(&:flip)
    cube + inner
  end
  def volume(polygons)
    polygons.sum do |polygon|
      a=polygon.vertices.first
      (1...polygon.vertices.length-1).sum do |i|
        b=polygon.vertices[i]; c=polygon.vertices[i+1]
        a.dot(b.cross(c))/6.0
      end
    end
  end
  def assert_volume(expected,polygons)
    assert_in_delta expected,volume(polygons),1e-7
    assert polygons.all? { |p| p.vertices.length>=3 && p.vertices.all? { |v| v.to_a.all?(&:finite?) } }, 'invalid polygon output'
  end
  def test_overlapping_boxes
    assert_volume 1500,BSP.union(cube,cube(5))
  end
  def test_disjoint_boxes
    assert_volume 2000,BSP.union(cube,cube(30))
  end
  def test_coplanar_shared_face
    result=BSP.union(cube,cube(10))
    assert_volume 2000,result
    refute result.any? { |p| p.vertices.all? { |v| (v.x-10).abs<1e-8 } }, 'shared internal face remained'
  end
  def test_identical_boxes_are_idempotent
    assert_volume 1000,BSP.union(cube,cube)
  end
  def test_contained_solid_does_not_add_volume
    assert_volume 1000,BSP.union(cube,cube(3,3,3,4))
  end
  def test_sealed_cavity_survives_external_union
    assert_volume 1836,BSP.union(hollow,cube(9))
  end
  def test_solid_island_inside_cavity
    assert_volume 944,BSP.union(hollow,cube(4,4,4,2))
  end
  def test_cavity_partially_filled
    assert_volume 968,BSP.union(hollow,cube(5,3,3,4))
  end
  def test_cavity_filled_exactly
    assert_volume 1000,BSP.union(hollow,cube(3,3,3,4))
  end
  def test_overlap_of_two_cavities
    ai=cube(2,2,2,5); ai.each(&:flip)
    bi=cube(3,3,3,5); bi.each(&:flip)
    assert_volume 936,BSP.union(cube+ai,cube+bi)
  end
  def test_rotated_and_translated_geometry
    transform=lambda do |polygons|
      angle=0.37
      polygons.map do |p|
        points=p.vertices.map { |v| Geom::Point3d.new(v.x*Math.cos(angle)-v.y*Math.sin(angle)+57,v.x*Math.sin(angle)+v.y*Math.cos(angle)-29,v.z+11) }
        BSP::Polygon.new(points,p.source)
      end
    end
    assert_volume 1836,BSP.union(transform.call(hollow),transform.call(cube(9)))
  end
  def test_operand_order_preserves_volume
    assert_volume 1836,BSP.union(cube(9),hollow)
  end
  def test_material_provenance_survives_splitting
    result=BSP.union(cube(0,0,0,10,:green),cube(5,0,0,10,:gold))
    assert_equal [:gold,:green],result.map(&:source).uniq.sort
  end
  def test_inputs_are_unchanged
    a=hollow; b=cube(9)
    before=Marshal.dump([a,b])
    BSP.union(a,b)
    assert_equal before,Marshal.dump([a,b])
  end
  def test_empty_union
    assert_volume 1000,BSP.union([],cube)
    assert_volume 1000,BSP.union(cube,[])
  end
  def test_complexity_guard
    assert_raises(LSC::SuperCombine::CombineError) { BSP::Node.new([cube.first]*50_001) }
  end
  def test_mixed_outer_shell_directions_are_rejected
    reversed=cube(30,0,0,4).each(&:flip)
    assert_raises(LSC::SuperCombine::CombineError) { BSP.outer_direction([cube,reversed]) }
  end
  def test_wholly_reversed_disjoint_shells_are_recognized
    assert_equal(-1,BSP.outer_direction([cube.each(&:flip),cube(30).each(&:flip)]))
  end
  def test_cavity_and_island_directions_are_preserved
    assert_equal 1,BSP.outer_direction([cube,cube(3,3,3,4).each(&:flip),cube(4,4,4,2)])
  end
  def test_wholly_reversed_cavity_is_recognized
    assert_equal(-1,BSP.outer_direction([cube.each(&:flip),cube(3,3,3,4)]))
  end
  def test_shell_volume_is_stable_far_from_origin
    assert_in_delta 1000,BSP.signed_volume(cube(1e8,1e8,1e8)),1e-6
  end
end
