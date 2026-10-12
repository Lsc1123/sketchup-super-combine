# frozen_string_literal: true
# Minimal Euclidean math adapter for exercising the real BSP kernel in plain Ruby.
# This is NOT a SketchUp emulator: no entities, native CSG or Length tolerance.
module Geom
  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x, y=nil, z=nil)
      @x, @y, @z = (y.nil? ? x : [x,y,z]).map(&:to_f)
    end
    def dot(other)
      x*other.x + y*other.y + z*other.z
    end
    def cross(other)
      Vector3d.new(y*other.z-z*other.y, z*other.x-x*other.z, x*other.y-y*other.x)
    end
    def normalize
      length = Math.sqrt(dot(self))
      raise ArgumentError, 'Zero vector' if length.zero?
      Vector3d.new(x/length,y/length,z/length)
    end
    def reverse
      Vector3d.new(-x,-y,-z)
    end
    def to_a
      [x,y,z]
    end
  end
  class Point3d < Vector3d
    def -(other)
      Vector3d.new(x-other.x,y-other.y,z-other.z)
    end
  end
  def self.linear_combination(a,p,b,q)
    Point3d.new(a*p.x+b*q.x,a*p.y+b*q.y,a*p.z+b*q.z)
  end
end
