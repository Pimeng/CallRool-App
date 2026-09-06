# 快捷考勤

一个面向班委、教师和活动组织者的轻量级 Flutter 点名工具。打开应用即可使用内置示例名单，也可以通过 TXT 文件导入自己的名单；考勤数据会保存在本机，方便在下一次启动时继续使用。

## 功能

- 名单管理：添加、删除、批量选择、拖拽调整顺序。
- 快速点名：一键标记“正常”或选择“缺勤、公假、事假、病假”。
- 批量操作：全选、反选，并为已选人员批量设置考勤状态。
- 搜索与筛选：支持按姓名、拼音全拼和拼音首字母搜索；可筛选全部、未点名、正常和缺勤人员。
- 数据统计：实时显示未点名、正常、缺勤和请假人数。
- 名单导入/导出：支持按“一行一个名字”的格式导入或导出 `.txt` 文件，可追加或替换现有名单，并自动忽略空行和重复姓名。
- 考勤记录：可复制当前考勤汇总到剪贴板，也可以将本次考勤全部重置为“未点名”。
- 课程关联：可同步 WakeUp 分享课程表，复制考勤汇总时自动附带当前课程、教师、教室和时间。
- 便捷收尾：支持将所有尚未点名的人员一次性标记为缺勤。
- 响应式界面：适配窄屏和宽屏窗口，适合 Android 与 Windows 使用。

## 默认行为与数据保存

首次启动时会自动创建 10 人示例名单：

```text
刘一 陈二 张三 李四 王五 赵六 孙七 周八 吴九 郑十
```

名单及每个人当前的考勤状态使用 `shared_preferences` 保存在本机，不依赖服务器或账号登录。应用卸载、清除应用数据或手动删除本地存储后，数据可能会丢失；导出 TXT 可作为简单备份。

## WakeUp 课程表同步

在右上角“名单操作”菜单中选择“同步 WakeUp 课程表”，填写 `authToken` 和 `shareCode`：

- `authToken` 会保存在本机，下次同步时自动填入。
- `shareCode` 每次同步时手动填写，不会保存。
- 分享码过期或课程表为空时会显示错误，并保留上一次成功同步的课程表。
- 成功同步后，复制考勤情况时会根据开学日期、当前周次、星期和节次附带当前课程信息。

## 环境要求

- Flutter SDK，且 Dart SDK 满足 `pubspec.yaml` 中的约束：`^3.13.2`
- Android 开发环境（运行 Android 版本时）
- Windows 桌面开发环境（运行 Windows 版本时）

查看本机 Flutter 环境：

```bash
flutter doctor
```

## 快速开始

```bash
git clone <仓库地址>
cd callrool_app
flutter pub get
flutter run
```

如果电脑连接了多个设备，可以先查看设备列表，再指定目标设备：

```bash
flutter devices
flutter run -d <device-id>
```

## 开发命令

```bash
# 运行静态检查
flutter analyze

# 运行测试
flutter test

# 构建 Android APK
flutter build apk --release

# 构建 Windows 应用
flutter build windows --release
```

## 导入名单格式

TXT 文件使用 UTF-8 文本编码，每行一个姓名。例如：

```text
张三
李四
王五
```

导入时可以选择：

- **追加**：保留现有名单，并加入新姓名；与现有名单重复的姓名会被跳过。
- **替换现有**：清空当前名单后导入文件内容。

## 项目结构

```text
lib/
├── main.dart                         # 应用入口、页面状态和主要交互逻辑
├── models/
│   ├── attendance.dart                # 考勤状态、颜色、图标和筛选枚举
│   └── person.dart                    # 人员模型及本地存储序列化
└── widgets/
    └── attendance_widgets.dart        # 人员行、状态按钮和空名单组件
test/
└── widget_test.dart                   # 首次启动和默认名单测试
```

## 依赖

主要依赖包括：

- [`file_picker`](https://pub.dev/packages/file_picker)：选择和保存 TXT 文件
- [`lpinyin`](https://pub.dev/packages/lpinyin)：姓名拼音及首字母搜索
- [`shared_preferences`](https://pub.dev/packages/shared_preferences)：本地保存名单和考勤状态
