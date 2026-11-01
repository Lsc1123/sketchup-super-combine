# frozen_string_literal: true
# Load only in an isolated SketchUp instance, then call SuperCombineNativeAudit.run.
# Does not auto-run. Requires an empty top-level document; saved scratch paths
# must be explicitly supplied by the caller, after isolating the host instance.
require 'json'
require 'fileutils'
require 'digest'
require_relative '../src/lsc_super_combine/engine' unless defined?(LSC::SuperCombine::Engine)

module SuperCombineNativeAudit
  extend self
  E = LSC::SuperCombine::Engine
  BSP = LSC::SuperCombine::BSP
  OUTPUT = File.expand_path('../test-results/audit-native.json',__dir__)

  def cube(es, x=0, y=0, z=0, size=10)
    group = es.add_group
    face = group.entities.add_face([[x,y,z],[x+size,y,z],[x+size,y+size,z],[x,y+size,z]])
    raise 'Fixture face could not be created' unless face
    face.reverse! if face.normal.z < 0
    face.pushpull(size)
    group
  end

  def snapshot(sources)
    sources.map do |s|
      {id: s.persistent_id, valid: s.valid?, volume: s.volume,
       transform: s.transformation.to_a,
       faces: E.definition(s).entities.grep(Sketchup::Face).map do |f|
         [f.vertices.map { |v| v.position.to_a }, f.normal.to_a, f.material&.name, f.back_material&.name]
       end}
    end
  end

  def combine_case(model, sources, expected, shells=nil)
    model.selection.clear
    model.selection.add(sources)
    before = snapshot(sources)
    root_ids = model.active_entities.map(&:persistent_id).sort
    begin
      result, stats = E.combine(model)
      actual = result.volume.abs
      count = BSP.shells(result).length
      {pass: (actual-expected).abs <= [expected.abs*1e-6,1e-9].max && E.solid?(result) &&
             (shells.nil? || count==shells) && sources.none?(&:valid?) && model.selection.to_a==[result],
       outcome: 'success', expected_volume_in3: expected, actual_volume_in3: actual,
       absolute_volume_error_in3: (actual-expected).abs,
       expected_shells: shells, actual_shells: count, solid: E.solid?(result), stats: stats,
       source_ids: before.map { |s| s[:id] }, sources_replaced: sources.none?(&:valid?),
       result_selected: model.selection.to_a==[result]}
    rescue LSC::SuperCombine::CombineError => error
      intact = sources.all?(&:valid?) && snapshot(sources)==before &&
               model.active_entities.map(&:persistent_id).sort==root_ids
      selected = model.selection.map(&:persistent_id).sort==sources.map(&:persistent_id).sort
      {pass: false, outcome: 'rejected', error: error.message, sources_intact: intact,
       selection_restored: selected, expected_volume_in3: expected}
    end
  end

  def run(output=OUTPUT, disposable_path: nil)
    model = Sketchup.active_model
    disposable = model.path.empty? || (disposable_path && model.path==File.expand_path(disposable_path))
    raise 'Use a new, empty, top-level disposable model' unless
      disposable && model.entities.length.zero? && model.active_path.nil?
    raise 'Another validation bridge is loaded; use an isolated instance' if defined?(AMW::Bridge)
    @model = model
    @report = {scope: 'SketchUp native engine', sketchup: Sketchup.version,
               ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM, pid: Process.pid,
               version: LSC::SuperCombine::VERSION,
               engine_sha256: Digest::SHA256.file(E.method(:combine).source_location.first).hexdigest,
               bsp_sha256: Digest::SHA256.file(BSP.method(:combine).source_location.first).hexdigest,
               results: []}
    @output = output
    scenarios = {
      'outward_disjoint_shells' => proc do
        a=cube(model.entities); cube(a.entities,30,0,0,4).explode
        combine_case(model,[a,cube(model.entities,60,0,0,2)],1072,3)
      end,
      'mixed_orientation_disjoint_shells' => proc do
        a=cube(model.entities); inner=cube(a.entities,30,0,0,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        accepted=E.solid?(a); input_volume=a.volume
        result=combine_case(model,[a,cube(model.entities,60,0,0,2)],1072,3)
        safe_rejection=result[:outcome]=='rejected' && result[:sources_intact] && result[:selection_restored]
        result.merge(pass: result[:pass] || safe_rejection,
                     safe_rejection: safe_rejection,
                     input_passed_solid_check: accepted, input_reported_volume_in3: input_volume)
      end,
      'reversed_single_shell_native_union' => proc do
        a=cube(model.entities); a.entities.grep(Sketchup::Face).each(&:reverse!)
        combine_case(model,[a,cube(model.entities,5)],1500,1)
      end,
      'mixed_orientation_third_cube_within_bounds' => proc do
        a=cube(model.entities); inner=cube(a.entities,30,0,0,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        result=combine_case(model,[a,cube(model.entities,20,0,0,2)],1072,3)
        safe_rejection=result[:outcome]=='rejected' && result[:sources_intact] && result[:selection_restored]
        result.merge(pass:result[:pass] || safe_rejection,safe_rejection:safe_rejection)
      end,
      'sealed_cavity' => proc do
        a=cube(model.entities); inner=cube(a.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        combine_case(model,[a,cube(model.entities,9)],1836,2)
      end,
      'wholly_reversed_cavity' => proc do
        a=cube(model.entities); inner=cube(a.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        a.entities.grep(Sketchup::Face).each(&:reverse!)
        combine_case(model,[a,cube(model.entities,9)],1836,2)
      end,
      'wholly_reversed_disjoint_shells' => proc do
        a=cube(model.entities); cube(a.entities,30,0,0,4).explode
        a.entities.grep(Sketchup::Face).each(&:reverse!)
        combine_case(model,[a,cube(model.entities,60,0,0,2)],1072,3)
      end,
      'mirrored_nonuniform_nested' => proc do
        wrapper=model.entities.add_group
        cube(wrapper.entities)
        wrapper.transformation=Geom::Transformation.translation([20,0,0])*Geom::Transformation.scaling(-2,1,1)
        combine_case(model,[wrapper,cube(model.entities,15)],2500,1)
      end,
      'small_scale' => proc do
        combine_case(model,[cube(model.entities,0,0,0,0.01),cube(model.entities,0.005,0,0,0.01)],1.5e-6,1)
      end,
      'overlap_below_kernel_epsilon_native' => proc do
        combine_case(model,[cube(model.entities),cube(model.entities,10-5e-6)],1999.9995,1)
      end,
      'overlap_below_kernel_epsilon_cavity' => proc do
        a=cube(model.entities); inner=cube(a.entities,3,3,3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        combine_case(model,[a,cube(model.entities,10-5e-6)],1935.9995,2)
      end,
      'large_translation_native' => proc do
        combine_case(model,[cube(model.entities,1e8,1e8,1e8),cube(model.entities,1e8+5,1e8,1e8)],1500,1)
      end,
      'large_translation_cavity' => proc do
        a=cube(model.entities,1e8,1e8,1e8)
        inner=cube(a.entities,1e8+3,1e8+3,1e8+3,4)
        inner.entities.grep(Sketchup::Face).each(&:reverse!); inner.explode
        combine_case(model,[a,cube(model.entities,1e8+9,1e8,1e8)],1836,2)
      end,
      'unrepairable_rollback' => proc do
        a=cube(model.entities)
        a.entities.grep(Sketchup::Face).select { |f| f.normal.z>0.5 || f.normal.x>0.5 }.each(&:erase!)
        result=combine_case(model,[a,cube(model.entities,30)],0)
        result.merge(pass: result[:outcome]=='rejected' && result[:sources_intact] && result[:selection_restored])
      end,
      'shared_parent_component_edit' => proc do
        wrapper=model.entities.add_group
        a=cube(wrapper.entities); b=cube(wrapper.entities,5)
        component=wrapper.to_component
        outside=model.entities.add_instance(component.definition,Geom::Transformation.translation([100,0,0]))
        before=outside.definition.entities.map(&:persistent_id)
        model.active_path=[component]
        result=combine_case(model,[a,b],1500,1)
        after=outside.definition.entities.map(&:persistent_id)
        model.active_path=nil
        result.merge(shared_definition_changed: before!=after,
                     interpretation: 'Standard component edit propagation; product/documentation decision',
                     outside_instance_valid: outside.valid?)
      end
    }
    scenarios.each do |name, scenario|
      started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        result=scenario.call
      rescue StandardError, SystemStackError => error
        result={pass: false, outcome: 'fixture_or_runner_error', error: "#{error.class}: #{error.message}", trace: error.backtrace.first(5)}
      ensure
        model.active_path=nil if model.active_path
        model.entities.clear!
      end
      @report[:results] << result.merge(name: name,seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)
      save
    end
    # A timer separates undo from the event that commits the operation.
    start_undo(false)
    @report
  end

  def start_undo(nested)
    model=@model
    raise 'Audit model is no longer active' unless Sketchup.active_model==model
    model.entities.clear!
    root=nested ? model.entities.add_group : nil
    model.active_path=[root] if root
    es=model.active_entities
    model.start_operation('Audit fixtures',true)
    sources=[cube(es),cube(es,5)]
    model.commit_operation
    ids=sources.map(&:persistent_id).sort
    model.selection.add(sources)
    E.combine(model)
    UI.start_timer(0.1,false) do
      begin
        raise 'Audit model is no longer active' unless Sketchup.active_model==model
        Sketchup.undo
        UI.start_timer(0.1,false) do
          begin
            actual=model.active_entities.map(&:persistent_id).sort
            @report[:results] << {name: nested ? 'nested_one_undo' : 'top_level_one_undo',
                                 pass: actual==ids,expected_ids: ids,actual_ids: actual}
            model.active_path=nil if model.active_path
            model.entities.clear!
            save
            nested ? finish : start_undo(true)
          rescue StandardError => error
            fail_async(error)
          end
        end
      rescue StandardError => error
        fail_async(error)
      end
    end
  end

  def save
    FileUtils.mkdir_p(File.dirname(@output))
    File.write(@output,JSON.pretty_generate(@report)+"\n")
  end

  def finish
    @report[:complete]=true
    save
    puts "Super Combine audit complete: #{@output}"
  end

  def fail_async(error)
    @report[:runner_error]="#{error.class}: #{error.message}"
    save
  end
end
