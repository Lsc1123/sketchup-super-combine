# 参与开发

欢迎提交缺陷、最小复现模型和改进建议。项目使用 MIT；BSP 内核的 csg.js 来源与 MIT 声明位于 `src/lsc_super_combine/THIRD_PARTY_NOTICES.txt`。

## 环境与检查

CI 使用 Ruby 3.2、Python 3.12，在 macOS 与 Windows 上运行，无第三方 Python 依赖：

```sh
ruby tools/check_syntax.rb
ruby tests/bsp_test.rb
ruby tests/entrypoint_test.rb
ruby tests/bounds_test.rb
python -m unittest discover -s tests -p "test_*.py" -v
python tools/package.py
```

源码入口为 `src/lsc_super_combine.rb`，运行代码使用 `LSC::SuperCombine` 命名空间。版本只在 `src/lsc_super_combine/version.rb` 定义。增加运行文件时更新 `tools/package_manifest.json`；不要靠遍历整个源码目录打包。

## 原生验证

纯 Ruby 测试不模拟 SketchUp 实体 API。修改几何、事务、材质或撤销行为时，应在独立、可丢弃的空白文档中加载插件及原生测试。不得在工作模型中运行测试，不得中断其他开发者的实例；共享自动启动桥需先协调暂停、测试后原样恢复。

`tests/native.rb` 包含基本几何测试；`tests/audit_native.rb` 包含几何边界及异步撤销检查，加载后需显式调用 `SuperCombineNativeAudit.run`。结果只有在 `complete=true` 且无 `runner_error` 时才算完整。Windows 未实际运行过的项目必须标注未验证。

`tests/audit_bsp.rb` 是内核边界探查，包含不满足正常内核方向/容差假设的输入，可能返回非零；不能把它的失败直接等同于插件失败。首次审查快照在 `docs/audit/2026-11-01/`，发布验证在 `docs/validation/v1.0.1/`。

## 提交问题与改动

提供 SketchUp / 插件 / 操作系统版本、复现步骤、预期与实际结果。模型尽量简化为合成几何；说明是否涉及洞口、空腔、反向面、嵌套或缩放。PR 说明行为变化、验证命令及仍未覆盖的平台。

## 维护者发布

更新版本文件、CHANGELOG、`docs/releases/vX.Y.Z.md`，完成原生验证并合入。为同一提交推送对应 `vX.Y.Z` tag。CI 在两平台测试并生成字节一致的 RBZ，确认 tag 与版本一致后发布 Release、安装包与 SHA256。不要重写已发布 tag 或替换旧版本的安装包。
