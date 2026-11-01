# encoding: UTF-8
require File.join(__dir__, 'bsp')
require File.join(__dir__, 'version')
module LSC
  module SuperCombine
    class CombineError < StandardError; end
    module Engine
      extend self
      IDENTITY = Geom::Transformation.new unless const_defined?(:IDENTITY)

      def instance?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def geometry?(entity)
        entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
      end

      def definition(entity)
        entity.is_a?(Sketchup::Group) ? entity.entities.parent : entity.definition
      end

      def solid?(group)
        group.valid? && group.manifold? && group.volume.abs > 1.0e-9 &&
          group.entities.all? { |e| geometry?(e) } &&
          group.entities.grep(Sketchup::Edge).all? { |e| e.faces.length == 2 }
      end

      # Never edit an original definition: all operations work in a disposable container.
      # Using native explode retains UV coordinates, transformations and per-face materials.
      def flatten(source, transform, destination, batches, inherited_material = nil, depth = 0)
        raise CombineError, '嵌套超过 100 层，请先简化模型。' if depth > 100
        raise CombineError, '选择中含锁定的群组或组件，请先解锁。' if source.locked?
        defn = definition(source)
        raise CombineError, '嵌套对象含粘附切洞组件，请先将洞口转为实际几何。' if defn.behavior.cuts_opening?
        children = defn.entities.select { |e| instance?(e) }
        unsupported = defn.entities.reject { |e| instance?(e) || geometry?(e) || e.is_a?(Sketchup::ConstructionLine) || e.is_a?(Sketchup::ConstructionPoint) }
        raise CombineError, '对象中含文字、标注、图片等非几何内容，请先移出后再组合。' unless unsupported.empty?
        material = source.material || inherited_material
        accumulated = transform * source.transformation
        if defn.entities.any? { |e| geometry?(e) }
          group = destination.add_group
          copy = group.entities.add_instance(defn, accumulated)
          copy.material = material if material
          copy.explode
          # Copied descendants are discarded here, then copied recursively from the original.
          group.entities.select { |e| !geometry?(e) }.each(&:erase!)
          batches << group
        end
        children.each { |child| flatten(child, accumulated, destination, batches, material, depth + 1) }
      end

      def edge_components(edges)
        pending = edges.to_h { |e| [e, true] }
        components = []
        until pending.empty?
          first = pending.keys.first
          pending.delete(first)
          component = [first]
          cursor = 0
          while cursor < component.length
            component[cursor].vertices.each do |v|
              v.edges.each do |edge|
                next unless pending.delete(edge)
                component << edge
              end
            end
            cursor += 1
          end
          components << component
        end
        components
      end

      def orient_faces(group)
        pending = group.entities.grep(Sketchup::Face).to_h { |f| [f, true] }
        until pending.empty?
          seed = pending.keys.first
          pending.delete(seed)
          queue = [seed]
          cursor = 0
          while cursor < queue.length
            face = queue[cursor]
            face.edges.each do |edge|
              next unless edge.faces.length == 2
              other = (edge.faces - [face]).first
              next unless pending.delete(other)
              other.reverse! if edge.reversed_in?(face) == edge.reversed_in?(other)
              queue << other
            end
            cursor += 1
          end
        end
      end

      def repair(group, stats)
        entities = group.entities
        stray = entities.grep(Sketchup::Edge).select { |e| e.faces.empty? }
        # A pure edge cage can produce faces; an otherwise valid solid keeps its holes.
        if entities.grep(Sketchup::Face).empty?
          stray.each { |e| e.find_faces if e.valid? }
        end
        return group if solid?(group)
        stray = entities.grep(Sketchup::Edge).select { |e| e.faces.empty? }
        stats[:stray_edges] += stray.length
        entities.erase_entities(stray) unless stray.empty?
        return group if solid?(group)

        # A partition is removable only if every perimeter edge is shared by extra faces.
        partitions = entities.grep(Sketchup::Face).select { |face| face.edges.all? { |edge| edge.faces.length == 3 } }
        partitions.each do |face|
          next unless face.valid? && face.edges.all? { |edge| edge.faces.length == 3 }
          face.erase!
          stats[:internal_faces] += 1
        end
        return group if solid?(group)

        boundaries = entities.grep(Sketchup::Edge).select { |e| e.faces.length == 1 }
        edge_components(boundaries).each do |edges|
          # Only a single closed, coplanar boundary is safe to cap. No invented bridges.
          vertices = edges.flat_map(&:vertices).uniq
          next unless vertices.all? { |v| (v.edges & edges).length == 2 }
          points = vertices.map(&:position)
          next if points.length < 3
          plane = Geom.fit_plane_to_points(points)
          next unless plane && points.all? { |p| p.distance_to_plane(plane).to_f.abs < 0.001 }
          before = entities.grep(Sketchup::Face).length
          edges.each { |e| e.find_faces if e.valid? && e.faces.length == 1 }
          stats[:repaired_faces] += [entities.grep(Sketchup::Face).length - before, 0].max
        end
        orient_faces(group)
        group
      end

      def issue_summary(group)
        edges = group.entities.grep(Sketchup::Edge)
        "#{edges.count { |e| e.faces.length == 1 }} 条开口边、#{edges.count { |e| e.faces.length > 2 }} 条多面共边"
      end

      def union(groups, stats)
        result = groups.shift
        groups.each_with_index do |other, index|
          Sketchup.set_status_text("超级组合：合并实体 #{index + 2}/#{stats[:solids]}")
          merged = result.union(other)
          raise CombineError, 'SketchUp 无法完成布尔合并（可能存在相切、小面或自相交），原对象已保留。' unless merged && solid?(merged)
          result = merged
        end
        result
      end

      # A finite union must preserve its input extents. Capture these before
      # native union consumes operands; topology checks alone cannot detect loss.
      def combined_bounds(groups)
        boxes = groups.map(&:bounds)
        [3.times.map { |axis| boxes.map { |b| b.min[axis].to_f }.min },
         3.times.map { |axis| boxes.map { |b| b.max[axis].to_f }.max }]
      end

      def verify_bounds!(group, expected)
        actual = [group.bounds.min.to_a, group.bounds.max.to_a]
        matches = 2.times.all? do |side|
          3.times.all? do |axis|
            value = actual[side][axis].to_f
            value.finite? && (value - expected[side][axis]).abs <= BSP::EPSILON
          end
        end
        return if matches
        raise CombineError, '组合结果范围与输入不一致，可能丢失几何。请统一独立壳体法线或分批处理；原对象已保留。'
      end

      def combine(model = Sketchup.active_model, selected = nil)
        sources = (selected || model.selection.to_a).select(&:valid?)
        raise CombineError, '请先选中要组合的群组或组件。' if sources.empty?
        raise CombineError, '请选择群组或组件；散线散面请先成组。' unless sources.all? { |e| instance?(e) }
        raise CombineError, '请在同一编辑层级选择对象。' unless sources.all? { |e| e.parent == model.active_entities.parent }
        raise CombineError, '请先解锁选中的对象。' if sources.any?(&:locked?)
        if sources.any? { |s| definition(s).behavior.cuts_opening? }
          raise CombineError, '含粘附切洞组件。请先将切洞转换为实际洞口几何再组合，以免丢失洞口。'
        end
        original_selection = model.selection.to_a
        stats = { inputs: sources.length, solids: 0, repaired_faces: 0, internal_faces: 0, stray_edges: 0 }
        started = false
        begin
          model.start_operation('超级组合', true)
          started = true
          work = model.active_entities.add_group
          batches = []
          sources.each { |source| flatten(source, IDENTITY, work.entities, batches) }
          raise CombineError, '选择中没有可组合的面或边线。' if batches.empty?
          solids, open_groups = [], []
          batches.each do |group|
            repair(group, stats)
            if solid?(group)
              solids << group
            elsif group.entities.grep(Sketchup::Face).empty?
              group.erase!
            else
              open_groups << group
            end
          end
          unless open_groups.empty?
            # Reunite fragments split across nesting levels, then create missing intersections.
            pool = work.entities.add_group
            open_groups.each do |group|
              pool.entities.add_instance(definition(group), group.transformation).explode
              group.erase!
            end
            geometry = pool.entities.to_a
            pool.entities.intersect_with(false, IDENTITY, pool.entities, IDENTITY, true, geometry)
            repair(pool, stats)
            raise CombineError, "无法安全修成封闭实体：#{issue_summary(pool)}。请检查缺失面或交叉面；原对象未改变。" unless solid?(pool)
            solids << pool
          end
          raise CombineError, '没有可形成实体的体积，原对象未改变。' if solids.empty?
          stats[:solids] = solids.length
          expected_bounds = combined_bounds(solids)
          result = if solids.length > 1 && solids.any? { |g| BSP.shells(g).length > 1 }
                     BSP.combine(solids, work.entities, stats)
                   else
                     union(solids, stats)
                   end
          raise CombineError, '结果未通过实体检查，原对象未改变。' unless solid?(result)
          verify_bounds!(result, expected_bounds)
          # Pull the verified result out of the staging group with a fresh unique definition.
          final = model.active_entities.add_group
          final.entities.add_instance(definition(result), result.transformation).explode
          final.name = '超级组合'
          final.layer = sources.first.layer
          final.set_attribute('LSC_SuperCombine', 'version', VERSION)
          final.set_attribute('LSC_SuperCombine', 'source_count', sources.length)
          raise CombineError, '输出实体检查失败，原对象未改变。' unless solid?(final)
          verify_bounds!(final, expected_bounds)
          work.erase!
          sources.each(&:erase!)
          model.selection.clear
          model.selection.add(final)
          stats[:volume_m3] = final.volume.abs * 0.000016387064
          stats[:faces] = final.entities.grep(Sketchup::Face).length
          model.commit_operation
          started = false
          [final, stats]
        rescue StandardError, SystemStackError => error
          model.abort_operation if started
          model.selection.clear
          model.selection.add(original_selection.select(&:valid?))
          raise error if error.is_a?(CombineError)
          raise CombineError, "组合失败，原对象已保留。#{error.class}: #{error.message}"
        ensure
          Sketchup.set_status_text('')
        end
      end
    end
  end
end
