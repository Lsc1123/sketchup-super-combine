# SketchUp 原生验证记录

日期：2026-10-13；环境：macOS / SketchUp 2026 26.0.428；版本：1.0.0。

- `native-report.json`：17 项几何、材质、组件独立性和失败回滚测试。
- `undo-report.json`：顶层编辑状态，一次撤销恢复两份原对象。
- `nested-undo-report.json`：嵌套编辑状态，一次撤销恢复两份原对象。
- `ui-report.json`：已安装插件的菜单调用成功、工具栏可见及输出实体体积。
- `verification-summary.json`：20 项通过及当时验证的 RBZ 摘要。

以上是已完成的本机 SketchUp 测试证据；GitHub Actions 双平台 CI 单独执行纯 Ruby 内核和打包测试。Windows SketchUp GUI 尚未实机验证。

原生测试 `tests/native.rb` 只能在可丢弃、未保存的测试文档中手动加载，不能在工作模型内运行。开发期测试场景曾因在打开操作期间切换 `active_path` 触发一次宿主崩溃；测试已改为在操作之外切换编辑层级，顶层和嵌套撤销随后均通过。插件自身不切换编辑层级。开发桥不进入源代码提交或安装包。
