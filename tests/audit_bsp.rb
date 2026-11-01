# frozen_string_literal: true
# Diagnostic probes, deliberately separate from the passing release test suite.
# Exit 1 means a probe differs from its geometric expectation; see the audit report.
abort 'Run this probe in standalone Ruby, never in SketchUp' if defined?(Sketchup)
require 'json'
require 'fileutils'
require_relative 'support/geom'
module LSC
  module SuperCombine
    class CombineError < StandardError; end
  end
end
require_relative '../src/lsc_super_combine/bsp'

module SuperCombineBSPAudit
  extend self
  BSP = LSC::SuperCombine::BSP

  def cube(x = 0, y = 0, z = 0, size = 10)
    points = [[x,y,z], [x+size,y,z], [x+size,y+size,z], [x,y+size,z],
              [x,y,z+size], [x+size,y,z+size], [x+size,y+size,z+size], [x,y+size,z+size]]
    [[0,3,2,1], [4,5,6,7], [0,1,5,4], [1,2,6,5], [2,3,7,6], [3,0,4,7]].map do |indices|
      BSP::Polygon.new(indices.map { |i| Geom::Point3d.new(points[i]) }, :audit)
    end
  end

  # Translate to a nearby reference before measuring, so the oracle does not
  # introduce the large-coordinate cancellation being investigated.
  def volume(polygons)
    return 0.0 if polygons.empty?
    origin = polygons.first.vertices.first
    polygons.sum do |p|
      a = p.vertices.first - origin
      (1...p.vertices.length-1).sum do |i|
        a.dot((p.vertices[i]-origin).cross(p.vertices[i+1]-origin)) / 6.0
      end
    end
  end

  def run(output)
    hollow = cube + cube(3,3,3,4).each(&:flip)
    cases = [
      ['outward_disjoint_shells', cube + cube(30,0,0,4), cube(60,0,0,2), 1072.0],
      ['mixed_orientation_disjoint_shells', cube + cube(30,0,0,4).each(&:flip), cube(60,0,0,2), 1072.0],
      ['cavity_preservation', hollow, cube(9), 1836.0],
      ['cavity_island', hollow, cube(4,4,4,2), 944.0],
      ['small_scale', cube(0,0,0,0.01), cube(0.005,0,0,0.01), 1.5e-6],
      ['large_translation', cube(1e8,1e8,1e8), cube(1e8+5,1e8,1e8), 1500.0],
      ['overlap_below_kernel_epsilon', cube, cube(10-5e-6), 2000.0-0.0005]
    ]
    results = cases.map do |name, a, b, expected|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        polygons = BSP.union(a,b)
        actual = volume(polygons)
        finite = polygons.all? { |p| p.vertices.all? { |v| v.to_a.all?(&:finite?) } }
        {name: name, expected_volume_in3: expected, actual_volume_in3: actual,
         pass: finite && (actual-expected).abs <= [expected.abs*1e-8,1e-12].max,
         polygon_count: polygons.length, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC)-started}
      rescue StandardError, SystemStackError => error
        {name: name, pass: false, error: "#{error.class}: #{error.message}"}
      end
    end
    benchmarks = [8,16,32].map do |count|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      polygons = cube
      (1...count).each { |i| polygons = BSP.union(polygons,cube(i*30)) }
      {disjoint_cubes: count, polygons: polygons.length,
       seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC)-started}
    end
    report = {scope: 'Pure Ruby BSP only; not SketchUp acceptance', ruby: RUBY_DESCRIPTION,
              results: results, benchmarks: benchmarks}
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output,JSON.pretty_generate(report)+"\n")
    puts JSON.pretty_generate(report)
    results.all? { |r| r[:pass] }
  end
end

if $PROGRAM_NAME == __FILE__
  output = ARGV.first || File.expand_path('../test-results/audit-bsp.json',__dir__)
  exit(SuperCombineBSPAudit.run(output) ? 0 : 1)
end
