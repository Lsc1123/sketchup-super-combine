# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'
require File.join(__dir__, 'lsc_super_combine', 'version')
module LSC
  module SuperCombine
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('超级组合', File.join(__dir__, 'lsc_super_combine', 'main'))
      extension.description = '一键展开嵌套群组与组件、修补平面缺口并合并为实体群组，保留洞口与空腔。'
      extension.version = VERSION
      extension.creator = 'LSC'
      extension.copyright = '2026 LSC'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
