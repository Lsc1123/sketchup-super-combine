# frozen_string_literal: true
# Capture the mixed-shell defect in an isolated, explicitly disposable model.
require_relative 'audit_native' unless defined?(SuperCombineNativeAudit)

module SuperCombineNativeCase
  extend self

  def capture(disposable_path:, output: File.expand_path('../test-results/native-session/case',__dir__))
    model=Sketchup.active_model
    raise 'Use the explicitly named empty scratch model' unless model.path==File.expand_path(disposable_path) &&
      model.entities.length.zero? && model.active_path.nil? && !defined?(AMW::Bridge)
    FileUtils.mkdir_p(output)
    model.start_operation('Audit mixed-shell fixtures',true)
    a=SuperCombineNativeAudit.cube(model.entities)
    small=SuperCombineNativeAudit.cube(a.entities,30,0,0,4)
    small.entities.grep(Sketchup::Face).each(&:reverse!)
    small.explode
    b=SuperCombineNativeAudit.cube(model.entities,60,0,0,2)
    model.commit_operation
    sources=[a,b]
    ids=sources.map(&:persistent_id).sort
    ray=[Geom::Point3d.new(61,1,-1),Z_AXIS]
    report={pid:Process.pid,sketchup:Sketchup.version,expected_volume_in3:1072,
            input_passed_solid_check:SuperCombineNativeAudit::E.solid?(a),
            third_cube_hit_before:!!model.raytest(ray,false),source_ids:ids}
    raise 'Failed to save input fixture' unless model.save_copy(File.join(output,'mixed-shell-before.skp'))
    begin
      result,stats=SuperCombineNativeAudit::E.combine(model,sources)
    rescue LSC::SuperCombine::CombineError => error
      actual=model.entities.map(&:persistent_id).sort
      intact=sources.all?(&:valid?) && actual==ids && !!model.raytest(ray,false)
      report.merge!(outcome:'rejected',error:error.message,sources_intact:intact,
                    third_cube_hit_after:!!model.raytest(ray,false),complete:true)
      raise 'Failed to save rejected fixture' unless model.save_copy(File.join(output,'mixed-shell-after.skp'))
      write(output,report)
      return report
    end
    report.merge!(actual_volume_in3:result.volume.abs,
                  output_shells:SuperCombineNativeAudit::BSP.shells(result).length,
                  result_solid:SuperCombineNativeAudit::E.solid?(result),
                  result_bounds_min:result.bounds.min.to_a,result_bounds_max:result.bounds.max.to_a,
                  sources_deleted:sources.none?(&:valid?),third_cube_hit_after:!!model.raytest(ray,false),stats:stats)
    raise 'Failed to save output fixture' unless model.save_copy(File.join(output,'mixed-shell-after.skp'))
    write(output,report)
    UI.start_timer(0.1,false) do
      begin
        raise 'Scratch model is no longer active' unless Sketchup.active_model==model
        Sketchup.undo
        UI.start_timer(0.1,false) do
          begin
            raise 'Scratch model is no longer active' unless Sketchup.active_model==model
            actual=model.entities.map(&:persistent_id).sort
            report.merge!(one_undo_restores_source_ids:actual==ids,
                          third_cube_hit_after_undo:!!model.raytest(ray,false),complete:true)
            write(output,report)
          rescue StandardError => error
            report[:runner_error]="#{error.class}: #{error.message}"
            write(output,report)
          end
        end
      rescue StandardError => error
        report[:runner_error]="#{error.class}: #{error.message}"
        write(output,report)
      end
    end
  end

  def write(output,report)
    File.write(File.join(output,'case-report.json'),JSON.pretty_generate(report)+"\n")
  end
end
