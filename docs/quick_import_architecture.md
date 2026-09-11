# 快捷导入架构

UI 只依赖 `QuickImportBackend`，并通过 `backend_binding.dart` 获取实现。

## 公开仓库

- `quick_import_backend.dart`：统一接口、错误类、分享码提取和 API 响应解码。
- `api_quick_import_backend.dart`：调用现有外部 API。
- `backend_binding.dart`：默认只导入并创建 `ApiQuickImportBackend`。

因此普通 clone、Debug、PR 和社区 Release 都不需要任何私有文件。

## 私有仓库约定

私有仓库应至少包含：

```text
lib/services/quick_import/local_quick_import_backend.dart
lib/services/quick_import/backend_binding.dart
test/
```

私有 binding 导入 `local_quick_import_backend.dart`，并使
`createQuickImportBackend()` 返回 `LocalQuickImportBackend`。官方 Release CI 使用
`tool/inject_quick_import_backend.sh` 仅复制这两个 Dart 文件，不会将整个私有仓库混入公开源码。

CI 需要配置：

- `QUICK_IMPORT_PRIVATE_TOKEN`：仅具有 `Pimeng/callrool-app-inner` 读权限的 token。
- `SYMBOL_ARCHIVE_TOKEN`：对 `Pimeng/callrool-app-inner` 具有 Release 读写权限的 token。

Release 产物只包含 APK 和签名证书指纹。`split-debug-info` 文件会压缩后上传到
`Pimeng/callrool-app-inner` 的私有 Release，不作为公开 GitHub Release Asset 发布。

`temp/` 只是迁移工作区，不是任何 App 运行时或 CI 依赖。

## Windows 本地构建

运行 `build.bat`构建 Release APK，或运行 `build.bat appbundle`构建 AAB。

脚本按以下顺序寻找私有源码：

1. 环境变量 `QUICK_IMPORT_PRIVATE_SOURCE` 指定的仓库根目录。
2. 公开仓库同级的 `callrool-app-inner/`。
3. 项目下的 `.official-private/`。
4. 迁移期间的 `temp/private-quick-import/`。

只有本地实现和私有 binding 同时存在时才会注入。否则脚本会使用
`backend_binding.api.dart` 恢复 API backend。构建成功或失败后都会删除注入文件并恢复公开 binding。
如果需要强制验证 API fallback，可在运行前设置 `QUICK_IMPORT_DISABLE_PRIVATE=1`。

本地构建符号保存在已忽略的 `private-symbol-output/` 目录，需要由发布者自行安全备份。
