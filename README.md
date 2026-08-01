# 随记（notes_app）

[![Build](https://github.com/susurrune/suiji-notes/actions/workflows/build-apk.yml/badge.svg)](https://github.com/susurrune/suiji-notes/actions/workflows/build-apk.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

轻量快速记录 + 结构化管理的个人笔记应用。
融合 **vivo 原子笔记**（分类管理 / 富文本 / 多媒介）与 **Google Keep**（极简速记 / 标签 / 颜色）的优点。

技术栈：Flutter · Riverpod · drift(SQLite/FTS5) · Supabase(Phase 3 同步)

## 已实现

**核心**
- **多形态速记**：文本/标题/清单/图片/项目符号/表格/分隔线块 + **手绘涂鸦**（画布→PNG）+ **语音笔记**（录音+ASR 转写）+ **图片 OCR**（端侧识别），任意混排，输入即存；空笔记退出自动删除；创建年月日全程可见
- **随笔栏**：日记式速记每天的小感想/句子，暖色质感 + 按日期分组时间线
- **分类管理**：文件夹（树形）+ 标签（三类）+ 颜色 + 置顶 + 重要度 + 回收站
- **全文检索**：FTS5 命中标题/正文/清单/**OCR 文字/语音转写**；按类型/标签/颜色组合筛选
- **清单待办**：聚合视图，优先级 + 截止时间，右滑完成、左滑操作，快捷新建
- **提醒**：笔记定时本地通知

**安全与同步**
- **密码加密笔记**：PBKDF2 + AES-GCM，密文存储、不入明文检索、锁定/解锁
- **Supabase 云同步**：账号登录、整篇同步、冲突弹窗（保留本地/采用云端）、媒体上传 Storage（配置见 `docs/supabase_schema.sql`）

**体验**
- 个人资料（头像上传 + 昵称 + 首页问候）、深色模式、网格/列表、导出 Markdown/TXT/**PDF**、撤销、全局 FadeForwards 转场、统一艺术化空态

## 云同步启用步骤

1. 在 [supabase.com](https://supabase.com) 创建免费项目
2. SQL Editor 执行 `docs/supabase_schema.sql`
3. 设置 → 云同步 → 填入项目 URL 与 anon/publishable key → 注册/登录 → 立即同步

## 快速开始

```bash
# 本机 Android 调试
flutter pub get
flutter run

# 单元测试（数据层 + 组件）
flutter test

# 分析
flutter analyze
```

> 构建 iOS 需要 macOS + Xcode + Apple 开发者账号（代码层保持 iOS 兼容）。
> Windows 上如遇 Kotlin 增量编译缓存报错，`android/gradle.properties` 已设
> `kotlin.incremental=false` 规避。

## 文档

- `docs/architecture.md` — 架构蓝皮书（设计原则 / 数据模型 / 检索 / 同步 / 模块结构 / 阶段计划）
- `docs/ia.md` — 信息架构（数据关系 + 交互路径 + 检索维度）

## 阶段进度

| 阶段 | 状态 |
|---|---|
| Phase 0 环境 / Phase 1 MVP | ✅ 完成并通过模拟器联调 |
| Phase 2 富文本/手绘/语音/OCR/提醒 | 待开始 |
| Phase 3 加密 + Supabase 同步 | 待开始 |
| Phase 4 AI 摘要/待办提取 | 待开始 |
