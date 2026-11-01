# encoding: UTF-8
require 'sketchup.rb'
require File.join(__dir__, 'engine')
module LSC
  module SuperCombine
    extend self
    def run
      return if @busy
      @busy = true
      begin
        group, stats = Engine.combine
        @last_report = stats
        Sketchup.set_status_text("超级组合完成 · #{stats[:inputs]} 个对象 → 1 个实体群组 · 补面 #{stats[:repaired_faces]} · 可撤销")
        group
      rescue CombineError => error
        UI.messagebox("超级组合\n\n#{error.message}")
        nil
      ensure
        @busy = false
      end
    end

    def help
      UI.messagebox("超级组合 #{VERSION}\n\n1. 在同一层级选中群组或组件（支持嵌套）。\n2. 点击工具栏「超级组合」，或右键 → 超级组合。\n3. 结果为一个实体群组，支持一次撤销恢复。\n\n保留实际洞口与空腔，删除实体交叠处的内部面。自动修补闭合共面缺口、清除孤立线和可识别的内部隔面。\n\n相离物体会成为同一个群组中的多个封闭体，不自动搭桥。严重缺面、相切或自交不能保证自动修复；失败保留原对象。散线散面请先成组。\n\n面材质尽量保留；分组层级、组件关联和原对象属性在组合后不再保留。")
    end

    unless file_loaded?(__FILE__)
      command = UI::Command.new('超级组合') { run }
      command.tooltip = '超级组合：选中对象 → 一个实体群组'
      command.status_bar_text = '展开嵌套、修补缺口、布尔合并；保留洞口和空腔。支持撤销。'
      command.small_icon = File.join(__dir__, 'icons', 'combine.png')
      command.large_icon = command.small_icon
      command.set_validation_proc { Sketchup.active_model.selection.any? { |e| Engine.instance?(e) } ? MF_ENABLED : MF_GRAYED }
      menu = UI.menu('Extensions').add_submenu('超级组合')
      menu.add_item(command)
      menu.add_item('使用说明') { help }
      UI.add_context_menu_handler do |context|
        context.add_item(command) if Sketchup.active_model.selection.any? { |e| Engine.instance?(e) }
      end
      @toolbar = UI::Toolbar.new('超级组合')
      @toolbar.add_item(command)
      @toolbar.restore
      @toolbar.show if @toolbar.get_last_state == TB_NEVER_SHOWN
      file_loaded(__FILE__)
    end
  end
end
