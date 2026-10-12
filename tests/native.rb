# Run only in an empty disposable SketchUp document. All fixtures live in a test container.
require 'json'
module SuperCombineNativeTests
  extend self
  E = LSC::SuperCombine::Engine unless const_defined?(:E)
  def check(value, message)
    raise message unless value
  end
  def cube(entities, x=0, y=0, z=0, size=10)
    group = entities.add_group
    face = group.entities.add_face([[x,y,z],[x+size,y,z],[x+size,y+size,z],[x,y+size,z]])
    face.reverse! if face.normal.z < 0
    face.pushpull(size)
    group
  end
  def close_volume(group, expected)
    check((group.volume.abs-expected).abs < 0.001, "volume #{group.volume}, expected #{expected}")
    check(E.solid?(group), 'result is not a solid')
    check(group.entities.all? { |e| E.geometry?(e) }, 'nested instances remained')
  end
  def run
    model = Sketchup.active_model
    raise 'Please use an empty test document' unless model.path.empty?
    test_root = model.entities.add_group
    test_root.transformation=Geom::Transformation.translation([10000,0,0])
    model.active_path = [test_root]
    report = []
    scenarios = {
      'overlap_union' => proc do |es|
        a=cube(es); b=cube(es,5)
        result,stats=E.combine(model,[a,b]); close_volume(result,1500)
        check(!a.valid? && !b.valid?, 'sources still present')
        check(stats[:solids]==2,'wrong solid count')
      end,
      'disjoint_solids' => proc do |es|
        result,_=E.combine(model,[cube(es),cube(es,30)])
        close_volume(result,2000)
      end,
      'coplanar_shared_face' => proc do |es|
        result,_=E.combine(model,[cube(es),cube(es,10)])
        close_volume(result,2000)
      end,
      'nested_transformed_components_and_external_instance' => proc do |es|
        wrapper=es.add_group
        source=cube(wrapper.entities).to_component
        original_faces=source.definition.entities.grep(Sketchup::Face).length
        outside=es.add_instance(source.definition,Geom::Transformation.translation([100,0,0]))
        wrapper.transform!(Geom::Transformation.translation([20,0,0])*Geom::Transformation.scaling(-2,1,1))
        b=cube(es,15)
        result,_=E.combine(model,[wrapper,b]); close_volume(result,2500)
        check(outside.valid? && outside.definition.entities.grep(Sketchup::Face).length==original_faces, 'external definition changed')
        check((outside.volume-1000).abs<0.001,'external volume changed')
      end,
      'missing_planar_face' => proc do |es|
        a=cube(es)
        a.entities.grep(Sketchup::Face).max_by { |f| f.bounds.center.z }.erase!
        result,stats=E.combine(model,[a,cube(es,5)])
        close_volume(result,1500)
        check(stats[:repaired_faces]==1, 'missing cap not counted')
      end,
      'stray_edge' => proc do |es|
        a=cube(es); a.entities.add_line([50,0,0],[60,0,0])
        result,stats=E.combine(model,[a]); close_volume(result,1000)
        check(stats[:stray_edges]==1,'stray not removed')
      end,
      'through_hole' => proc do |es|
        a=cube(es)
        cutter=cube(es,3,3,-5,4)
        # A 4x4 prism through the complete 10-high block.
        cutter.entities.grep(Sketchup::Face).max_by { |f| f.bounds.center.z }.pushpull(20)
        perforated=cutter.subtract(a)
        check(perforated && E.solid?(perforated),'hole fixture failed')
        close_volume(perforated,840)
        result,_=E.combine(model,[perforated,cube(es,9)])
        close_volume(result,1740)
        hit=model.raytest([Geom::Point3d.new(5,5,-10).transform(model.edit_transform),Z_AXIS.transform(model.edit_transform)], false)
        check(hit.nil?, 'through hole was capped')
      end,
      'sealed_cavity' => proc do |es|
        hollow=cube(es)
        inner=cube(hollow.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!)
        inner.explode
        check(hollow && E.solid?(hollow),'cavity fixture failed')
        close_volume(hollow,936)
        result,_=E.combine(model,[hollow,cube(es,9)])
        close_volume(result,1836)
      end,
      'cavity_with_inner_island' => proc do |es|
        a=cube(es); inner=cube(a.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        result,_=E.combine(model,[a,cube(es,4,4,4,2)])
        close_volume(result,944)
        check(LSC::SuperCombine::BSP.shells(result).length==3,'inner island/cavity lost')
      end,
      'cavity_partly_filled' => proc do |es|
        a=cube(es); inner=cube(a.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        result,_=E.combine(model,[a,cube(es,5,3,3,4)])
        close_volume(result,968)
      end,
      'two_overlapping_cavities' => proc do |es|
        a=cube(es); ai=cube(a.entities,2,2,2,5)
        ai.entities.grep(Sketchup::Face).each(&:reverse!); ai.explode
        b=cube(es); bi=cube(b.entities,3,3,3,5)
        bi.entities.grep(Sketchup::Face).each(&:reverse!); bi.explode
        result,_=E.combine(model,[a,b]); close_volume(result,936)
      end,
      'internal_partition' => proc do |es|
        a=cube(es)
        a.entities.add_face([[5,0,0],[5,10,0],[5,10,10],[5,0,10]])
        result,stats=E.combine(model,[a]); close_volume(result,1000)
        check(stats[:internal_faces]==1,'internal partition not removed')
      end,
      'faces_split_into_nested_groups' => proc do |es|
        wrapper=es.add_group; a=cube(wrapper.entities)
        faces=a.entities.grep(Sketchup::Face)
        faces.each do |face|
          part=wrapper.entities.add_group
          part.entities.add_face(face.outer_loop.vertices.map(&:position))
        end
        a.erase!
        result,_=E.combine(model,[wrapper]); close_volume(result,1000)
      end,
      'cavity_with_through_hole_and_material' => proc do |es|
        a=cube(es); inner=cube(a.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        a.material='red'
        b=cube(es,20)
        cutter=cube(es,23,3,-5,4)
        cutter.entities.grep(Sketchup::Face).max_by { |f| f.bounds.center.z }.pushpull(20)
        b=cutter.subtract(b)
        result,_=E.combine(model,[a,b]); close_volume(result,1776)
        check(result.entities.grep(Sketchup::Face).any?(&:material),'inherited material missing')
      end,
      'duplicate_identical_solids' => proc do |es|
        result,_=E.combine(model,[cube(es),cube(es)])
        close_volume(result,1000)
      end,
      'rollback_unrepairable' => proc do |es|
        a=cube(es)
        faces=a.entities.grep(Sketchup::Face)
        faces.select { |f| f.normal.z>0.5 || f.normal.x>0.5 }.each(&:erase!)
        b=cube(es,30); before=es.length
        model.selection.clear; model.selection.add([a,b])
        begin
          E.combine(model)
          raise 'Expected failure'
        rescue LSC::SuperCombine::CombineError
          check(a.valid? && b.valid? && es.length==before,'rollback did not restore objects')
          check(model.selection.to_a.sort_by(&:entityID)==[a,b].sort_by(&:entityID),'selection not restored')
        end
      end,
      'locked_rollback' => proc do |es|
        a=cube(es); a.locked=true; before=es.length
        begin
          E.combine(model,[a]); raise 'Expected failure'
        rescue LSC::SuperCombine::CombineError
          check(a.valid? && a.locked? && es.length==before,'locked object changed')
        ensure
          a.locked=false if a.valid?
        end
      end
    }
    scenarios.each do |name, scenario|
      begin
        scenario.call(model.active_entities)
        report << {name:name, pass:true}
      rescue Exception => error
        report << {name:name, pass:false, error:error.message, trace:error.backtrace.first(4)}
      ensure
        model.active_entities.to_a.each { |e| e.locked=false if E.instance?(e) }
        model.active_entities.clear!
      end
    end
    model.active_path=nil
    test_root.erase! if test_root.valid?
    File.write(File.join(__dir__,'native-report.json'),JSON.pretty_generate(sketchup:Sketchup.version, results:report))
    report
  end
end
SuperCombineNativeTests.run
