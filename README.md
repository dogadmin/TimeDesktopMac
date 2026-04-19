# TimeDesktop for macOS

多时区桌面浮动时钟，纯 Objective-C / AppKit 原生实现，无 WebKit 依赖。

## 功能

- **多时区显示** — 同时显示最多 10 个时区的时间，覆盖全球主要城市
- **浮动窗口** — 无边框、半透明、置顶显示，不抢焦点
- **边缘停靠** — 吸附到屏幕四边，鼠标悬停自动展开，离开后自动折叠
- **菜单栏图标** — 左键点击显示/隐藏窗口，右键弹出完整菜单
- **全局快捷键** — `⌘⌥T` 快速切换显示/隐藏
- **中英双语** — 所有界面文本支持中文/English 切换
- **网络校时** — 从 worldtimeapi.org / Google 同步 UTC 时间
- **状态持久化** — 窗口位置、时区列表、主题、字号等设置自动保存

## 系统要求

- macOS 10.13 (High Sierra) 及以上
- Xcode Command Line Tools (`xcode-select --install`)

## 构建 & 运行

```bash
cd TimeDesktopMac/TimeDesktopMac
make run
```

单独构建：

```bash
make        # 编译 + 生成图标 → TimeDesktop.app
make clean  # 清理构建产物
```

## 项目结构

```
TimeDesktopMac/
└── TimeDesktopMac/
    ├── main.m            # 入口、AppDelegate、刷新定时器
    ├── ClockWindow.h/m   # 窗口、绘制、停靠、菜单、快捷键
    ├── TimezoneData.h/m  # IANA 时区数据（含中英文城市名）
    ├── NetTimeSync.h/m   # 网络时间同步
    ├── gen_icon.m        # 构建时生成 .icns 图标
    ├── Info.plist        # 应用元数据
    └── Makefile          # 构建脚本
```

## 右键菜单

| 功能 | 说明 |
|------|------|
| 添加/删除时区 | 按大洲分类选择城市 |
| 显示秒 | 切换 HH:mm / HH:mm:ss |
| 字号 | 小(13) / 中(16) / 大(20) / 特大(24) |
| 透明度 | 60% ~ 100% |
| 主题 | 深色 / 浅色 |
| 语言 | 中文 / English |
| 停靠 | 边缘停靠、方向、固定展开、隐藏、条带颜色/透明度 |
| 恢复默认 | 重置所有设置 |

## 技术细节

- `NSPanel` (非激活面板) 实现置顶浮动窗口
- Core Graphics 自绘圆角背景和文本
- Carbon Hot Key API 注册全局快捷键
- `NSTrackingArea` + 边缘轮询实现可靠的停靠展开/折叠
- `os_unfair_lock` 保护网络同步的线程安全
- `NSUserDefaults` 持久化应用状态
- `LSUIElement = true` 隐藏 Dock 图标

## License

MIT
