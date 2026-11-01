# encoding: UTF-8
# BSP operations adapted from Evan Wallace's csg.js (2011), MIT license.
# See THIRD_PARTY_NOTICES.txt. SketchUp mesh, UV and verification integration by LSC.
module LSC
  module SuperCombine
    module BSP
      extend self
      EPSILON = 1.0e-5 unless const_defined?(:EPSILON)
      def dot(normal, point)
        normal.x * point.x + normal.y * point.y + normal.z * point.z
      end
      class Polygon
        attr_accessor :vertices, :normal, :w
        attr_reader :source
        def initialize(vertices, source, normal=nil)
          @vertices, @source = vertices, source
          @normal = normal || (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).normalize
          @w = BSP.dot(@normal, vertices[0])
        end
        def copy
          Polygon.new(@vertices.dup, @source, @normal.clone)
        end
        def flip
          @vertices.reverse!
          @normal = @normal.reverse
          @w = -@w
        end
      end
      class Node
        def initialize(polygons=[], depth=0)
          @polygons=[]
          @depth=depth
          build(polygons)
        end
        def split(polygon, cf, cb, front, back)
          types = polygon.vertices.map do |v|
            d=BSP.dot(@normal,v)-@w
            d < -EPSILON ? 2 : (d > EPSILON ? 1 : 0)
          end
          case types.reduce(0,:|)
          when 0
            (@normal.dot(polygon.normal)>0 ? cf : cb) << polygon
          when 1 then front << polygon
          when 2 then back << polygon
          else
            f=[]; b=[]
            polygon.vertices.each_with_index do |v,i|
              j=(i+1)%types.length; vi=types[i]; vj=types[j]
              f << v unless vi==2
              b << v unless vi==1
              if (vi|vj)==3
                other=polygon.vertices[j]
                t=(@w-BSP.dot(@normal,v))/@normal.dot(other-v)
                point=Geom.linear_combination(1-t,v,t,other)
                f << point; b << point
              end
            end
            front << Polygon.new(f,polygon.source,polygon.normal.clone) if f.length>=3
            back << Polygon.new(b,polygon.source,polygon.normal.clone) if b.length>=3
          end
        end
        def build(polygons)
          return if polygons.empty?
          raise CombineError, '空腔布尔计算过于复杂，请拆成较小批次组合。' if @depth>256 || polygons.length>50_000
          unless @normal
            @normal=polygons.first.normal.clone; @w=polygons.first.w
          end
          front=[]; back=[]
          polygons.each { |p| split(p,@polygons,@polygons,front,back) }
          unless front.empty?
            @front ||= Node.new([],@depth+1)
            @front.build(front)
          end
          unless back.empty?
            @back ||= Node.new([],@depth+1)
            @back.build(back)
          end
        end
        def invert
          @polygons.each(&:flip)
          @normal=@normal.reverse if @normal
          @w=-@w if @w
          @front.invert if @front
          @back.invert if @back
          @front,@back=@back,@front
        end
        def clip_polygons(polygons)
          return polygons.dup unless @normal
          front=[]; back=[]
          polygons.each { |p| split(p,front,back,front,back) }
          front=@front.clip_polygons(front) if @front
          back=@back ? @back.clip_polygons(back) : []
          front+back
        end
        def clip_to(other)
          @polygons=other.clip_polygons(@polygons)
          @front.clip_to(other) if @front
          @back.clip_to(other) if @back
        end
        def all
          @polygons+(@front ? @front.all : [])+(@back ? @back.all : [])
        end
      end
      def union(a_polygons,b_polygons)
        a=Node.new(a_polygons.map(&:copy)); b=Node.new(b_polygons.map(&:copy))
        a.clip_to(b); b.clip_to(a); b.invert; b.clip_to(a); b.invert
        a.build(b.all)
        a.all
      end
      def shells(group)
        pending=group.entities.grep(Sketchup::Face).to_h { |f| [f,true] }
        result=[]
        until pending.empty?
          seed=pending.keys.first; pending.delete(seed)
          queue=[seed]; cursor=0
          while cursor<queue.length
            queue[cursor].edges.each do |edge|
              edge.faces.each { |f| queue << f if pending.delete(f) }
            end
            cursor+=1
          end
          result << queue
        end
        result
      end

      def signed_volume(polygons)
        origin=polygons.first.vertices.first
        polygons.sum do |polygon|
          a=polygon.vertices.first-origin
          (1...polygon.vertices.length-1).sum do |i|
            a.dot((polygon.vertices[i]-origin).cross(polygon.vertices[i+1]-origin))/6.0
          end
        end
      end

      # A cavity may point inward, but spatially independent outer shells must
      # agree. Bounds containment is used conservatively to identify outer
      # candidates; this is not a general self-intersection/containment solver.
      def outer_direction(shell_polygons)
        boxes=shell_polygons.map do |polygons|
          points=polygons.flat_map(&:vertices)
          [3.times.map { |axis| points.map { |p| p.to_a[axis] }.min },
           3.times.map { |axis| points.map { |p| p.to_a[axis] }.max }]
        end
        roots=boxes.each_index.reject do |i|
          boxes.each_index.any? do |j|
            next false if i==j
            contained=3.times.all? { |axis| boxes[j][0][axis]<=boxes[i][0][axis]+EPSILON && boxes[j][1][axis]>=boxes[i][1][axis]-EPSILON }
            larger=3.times.any? { |axis| boxes[j][0][axis]<boxes[i][0][axis]-EPSILON || boxes[j][1][axis]>boxes[i][1][axis]+EPSILON }
            contained && larger
          end
        end
        directions=roots.map do |i|
          volume=signed_volume(shell_polygons[i])
          raise CombineError, '外壳体积无法可靠判定，请检查退化面或自相交；原对象已保留。' unless volume.finite? && !volume.zero?
          volume<0 ? -1 : 1
        end.uniq
        unless directions.length==1
          raise CombineError, '独立外壳法线方向不一致，请统一法线或分开处理；原对象已保留。'
        end
        directions.first
      end

      def mesh(group)
        transformation=group.transformation
        faces=group.entities.grep(Sketchup::Face)
        by_face={}
        faces.each do |face|
          mesh=face.mesh(0)
          by_face[face]=mesh.polygons.map do |indices|
            points=indices.map { |index| mesh.point_at(index.abs).transform(transformation) }
            Polygon.new(points,[face,transformation])
          end
        end
        components=shells(group).map { |component| component.flat_map { |face| by_face.fetch(face) } }
        direction=outer_direction(components)
        polygons=faces.flat_map { |face| by_face.fetch(face) }
        # A completely reversed solid is common in imported SketchUp geometry.
        polygons.each(&:flip) if direction<0
        polygons
      end
      def apply_material(face, polygon)
        original,transformation=polygon.source
        face.material=original.material
        face.back_material=original.back_material
        return unless [original.material,original.back_material].compact.any?(&:texture)
        helper=original.get_UVHelper(true,true,Sketchup.create_texture_writer)
        inverse=transformation.inverse
        [true,false].each do |front|
          material=front ? original.material : original.back_material
          next unless material && material.texture
          mapping=polygon.vertices.first(3).flat_map do |p|
            uv=front ? helper.get_front_UVQ(p.transform(inverse)) : helper.get_back_UVQ(p.transform(inverse))
            [p,Geom::Point3d.new(uv.x/uv.z,uv.y/uv.z,1)]
          end
          face.position_material(material,mapping,front)
        end
      end
      def combine(groups, destination, stats)
        polygons=mesh(groups.first)
        groups.drop(1).each_with_index do |group,index|
          Sketchup.set_status_text("超级组合：保留空腔计算 #{index+2}/#{groups.length}")
          polygons=union(polygons,mesh(group))
          raise CombineError, '布尔结果过于复杂，请拆成较小批次组合。' if polygons.length>50_000
        end
        output=destination.add_group
        # Weld the BSP's T junctions before importing the complete mesh in one pass.
        # Incremental add_face followed by seam removal can leave coincident unwelded edges.
        mesh=Geom::PolygonMesh.new
        unique={}
        polygons.each { |p| p.vertices.each { |v| unique[v.to_a.map { |n| (n/EPSILON).round }]=v } }
        points=unique.values
        sorted=(0..2).map { |axis| points.sort_by { |p| p[axis] } }
        polygons.each do |polygon|
          loop=[]
          polygon.vertices.each_with_index do |a,index|
            b=polygon.vertices[(index+1)%polygon.vertices.length]
            vector=b-a
            next if vector.length.to_f<EPSILON
            axis=(0..2).max_by { |i| vector[i].abs }
            low,high=[a[axis],b[axis]].minmax
            candidates=sorted[axis]
            first=candidates.bsearch_index { |p| p[axis].to_f>=low.to_f-EPSILON } || candidates.length
            last=candidates.bsearch_index { |p| p[axis].to_f>high.to_f+EPSILON } || candidates.length
            on_edge=candidates[first...last].filter_map do |point|
              t=(point-a).dot(vector)/(vector.length**2)
              next unless t>=-EPSILON && t<1-EPSILON
              nearest=Geom.linear_combination(1-t,a,t,b)
              [t,point] if point.distance(nearest).to_f<EPSILON
            end
            loop.concat(on_edge.sort_by(&:first).map { |_,point| mesh.add_point(point) })
          end
          mesh.add_polygon(loop.uniq) if loop.uniq.length>=3
        end
        stats[:mesh_points]=mesh.count_points
        stats[:mesh_polygons]=mesh.count_polygons
        stats[:fill]=output.entities.fill_from_mesh(mesh,true,0)
        stats[:before_faces]=output.entities.grep(Sketchup::Face).length
        output.entities.grep(Sketchup::Face).each do |face|
          triangle=face.mesh(0)
          vertices=triangle.polygon_at(1).map { |i| triangle.point_at(i.abs) }
          center=Geom::Point3d.new((0..2).map { |axis| vertices.sum { |p| p[axis] }/vertices.length })
          polygon=polygons.find do |p|
            (BSP.dot(p.normal,center)-p.w).abs<EPSILON &&
              p.vertices.each_with_index.all? { |v,i| (p.vertices[(i+1)%p.vertices.length]-v).cross(center-v).dot(p.normal)>=-EPSILON }
          end
          raise CombineError, '空腔计算表面映射失败，原对象已保留。' unless polygon
          face.reverse! if face.normal.dot(polygon.normal)<0
          apply_material(face,polygon)
        end
        # Remove triangulation seams only when both sides have identical appearance.
        output.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid? && edge.faces.length==2
          a,b=edge.faces
          next unless a.normal.samedirection?(b.normal) && a.material==b.material && a.back_material==b.back_material
          next if [a.material,a.back_material].compact.any?(&:texture)
          edge.erase! if b.vertices.all? { |v| v.position.distance_to_plane(a.plane).to_f.abs<EPSILON }
        end
        stray=output.entities.grep(Sketchup::Edge).select { |e| e.faces.empty? }
        output.entities.erase_entities(stray) unless stray.empty?
        stats[:cavity_kernel]=true
        output
      end
    end
  end
end
