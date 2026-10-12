# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'
module LSC
  module SuperCombine
    VERSION = '1.0.0' unless const_defined?(:VERSION)
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('超级组合', 'lsc_super_combine/main')
      extension.description = '一键展开嵌套群组与组件、修补平面缺口并合并为实体群组，保留洞口与空腔。'
      extension.version = VERSION
      extension.creator = 'LSC'
      extension.copyright = '2026 LSC'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
