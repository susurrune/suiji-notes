# 随记 — 架构蓝皮书

> 项目代号：**随记**（包名 `notes_app`）
> 定位：轻量快速记录 + 结构化管理的个人笔记应用（融合 vivo 原子笔记 + Google Keep）
> 状态：MVP 开发中（2026-08-01 立项）

## 0. 已确认决策

| 维度 | 决策 |
|---|---|
| 目标平台 | 移动端原生 Android/iOS（Flutter 单代码库）；本机仅构建 Android，iOS 需 macOS |
| UI 框架 | Flutter 3.44.8 / Dart 3.12 |
| 状态管理 | Riverpod |
| 本地存储 | drift (SQLite) + FTS5 全文索引 |
| 云同步 | Supabase（Postgres + Auth + Realtime + Storage），本地优先架构 |
| 加密 | AES-256-GCM + flutter_secure_storage + local_auth（生物识别） |
| ASR / OCR | speech_to_text / google_mlkit（端侧离线优先） |
| 导出 | TXT / Markdown（MVP），PDF（Phase 3） |

## 1. 核心设计原则

1. **统一笔记模型 + 块（Block）架构**：速记卡片与文档笔记是同一模型的不同渲染密度，天然支持混排。
2. **本地优先（Local-first）**：本地 SQLite 是唯一事实源，离线全功能可用；同步引擎后台推拉，绝不静默丢数据。
3. **同步就绪（Sync-ready from day 1）**：MVP 不做同步，但存储层带 outbox 变更日志，Phase 3 直接接 Supabase。
4. **模块解耦**：`core/`（模型/存储/仓库/同步/检索/导出）与 `features/`（业务页面）与 `ui/`（共享组件）严格分层。
5. **搜索含 OCR/ASR 来源文本，加密笔记隔离**：每块文本带 `source` 标记；加密笔记独立存储、不入明文索引。

## 2. 信息架构与数据模型

见 `docs/ia.md`（关系图）。核心实体：

- **Note**：`id, title(派生), color, pinned, important(0-3), folderId, encrypted, archived, trashTime, reminderAt, createdAt, updatedAt, deletedAt`
- **Block**（Note 的内容块集合，有序）：`id, noteId, type, data, source(manual|image_ocr|voice_asr), orderIndex`
  - type: `text(富文本) | checklist | image | drawing | voice | table | heading | bullet | divider`
- **Folder**（树）：`id, name, parentId, sortOrder, createdAt`
- **Tag**：`id, name, kind(alpha|numeric|shape), createdAt`；**NoteTag** 多对多
- **Media**：`id, noteId, blockId, localPath, remoteUrl, mime, size, status(pending|uploaded)`
- **ChangeLog**（outbox，为同步预留）：`id, entity, entityId, op, version, ts, payload`
- **EncryptedStore**：加密笔记隔离区，AES-256-GCM，密文存储

## 3. 全文检索设计

- FTS5 虚拟表索引：标题 + 所有文本块（含 OCR/ASR 转写文本）。
- **中文分词**：CJK 文本切分为单字 token（空格分隔）写入索引列，Latin 词保留原词；检索时对查询做同样切分后走 FTS5。
- 加密笔记**不写入**明文索引（搜索时按 id 排除，命中加密笔记仅提示"存在加密笔记，需解锁后查看"）。
- 千级笔记场景下 FTS5 毫秒级命中。

## 4. 同步架构（Phase 3 落地，MVP 预留）

```
本地 DB ──write──> ChangeLog(outbox)
同步引擎: push outbox ──> Supabase
           pull remote delta ──> 应用合并
冲突: 字段级 last-write-wins（版本号+设备id 决胜）
      整篇冲突 → UI 弹「合并 / 覆盖」提示，不静默丢数据
媒体: 本地文件 ──upload──> Supabase Storage（status 跟踪）
```

## 5. 代码结构

```
lib/
  main.dart
  core/
    domain/         # 纯 Dart 实体与值对象
    data/
      database/     # drift 表定义 + 数据库 + FTS5
      repositories/ # Note/Folder/Tag/Search 仓库
      sync/         # ChangeLog + SyncEngine 接口
      media/        # 媒体文件存储管理
    search/         # FTS5 检索服务（中文分词）
    export/         # txt/md 导出（Phase3 加 pdf）
    utils/
  features/
    quick_capture/  # 一键新建入口
    editor/         # 块编辑器
    notes/          # 列表/网格 + 筛选
    folders/        # 文件夹树
    tags/           # 标签管理
    todos/          # 待办视图
    search/         # 检索页
    trash/          # 回收站
    settings/       # 设置/主题/导出
  ui/
    theme/          # 浅/深主题（Material 3）
    widgets/        # 共享组件（卡片/手势容器/空态）
```

## 6. 分阶段计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | Flutter 环境 + 工程骨架 + Android 构建链 | ✅ 完成 |
| Phase 1 (MVP) | 速记 + 分类 + 检索 + 待办 + 回收站 + 导出 + 个人资料 | ✅ 完成 |
| Phase 2 | 表格/项目符号块 + 手绘涂鸦 + 语音(ASR) + 图片 OCR + 时间提醒 + 撤销 | ✅ 完成（模拟器验证） |
| Phase 3 | 密码加密(AES-GCM) + PDF 导出 + Supabase 云同步 | ✅ 完成（同步需用户配置 Supabase 项目） |
| Phase 4 | AI 摘要 / 待办自动提取 | 待开始 |

## 7. 非功能指标

- 千级笔记冷启动 / 列表滚动流畅（FTS5 + `drift` 惰性加载 + 分页列表）。
- 离线可用，联网后自动同步，冲突必提示。
- 手势（左右滑 / 下拉新建）带视觉反馈与可撤销操作。
