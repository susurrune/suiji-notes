# 随记 — 信息架构（IA）

## 数据模型关系图

```
┌────────────────────────────────────────────────────────────┐
│ Note（统一笔记模型）                                          │
│  id · title(可派生) · color · pinned · important(0-3)       │
│  folderId · encrypted · archived · trashTime · reminderAt   │
│  createdAt · updatedAt · deletedAt(软删)                    │
│  └─ blocks[] 内容块集合（有序，任意混排）                     │
│     text(富文本) | checklist | image | drawing(手绘)         │
│     voice(ASR转写) | table | heading | bullet | divider      │
│     每块带 source: manual|image_ocr|voice_asr（供搜索/筛选）  │
├────────────────────────────────────────────────────────────┤
│ 分类体系（双轨，互不冲突）                                    │
│  Folder（树形归档）          Tag（跨文件夹打标）               │
│  id·name·parentId·sortOrder  id·name·kind: alpha|num|shape   │
│  工作/学习/生活…             NoteTag 多对多                    │
├────────────────────────────────────────────────────────────┤
│ 附属：                                                       │
│  Media(图片/语音/手绘二进制, 含上传状态) · Trash(回收站)       │
│  EncryptedStore(加密隔离区, AES-256-GCM, 不入明文索引)         │
│  ChangeLog(outbox, 为云同步预留)                              │
└────────────────────────────────────────────────────────────┘
```

## 核心关系说明

| 关系 | 类型 | 说明 |
|---|---|---|
| Folder → Note | 1 : N（一篇笔记最多属于 1 个文件夹） | 归档结构，树形 |
| Folder → Folder | 自引用（父/子） | 多级分类，无限深度 |
| Tag ↔ Note | M : N（经 NoteTag） | 跨文件夹灵活打标 |
| Note → Block | 1 : N（有序） | 内容混排 |
| Note → Media | 1 : N | 二进制资源，独立管理上传状态 |
| Note → NoteTag → Tag | M : N | 组合筛选入口 |

## 交互路径（关键）

| 动作 | 路径 | 步数 |
|---|---|---|
| 新建速记 | 首页悬浮「+」→ 直接输入即存 | ≤ 1 |
| 从任意界面速记 | 全局悬浮球 → 输入即存 | ≤ 2 |
| 标记重要度 | 列表右滑 | 1 |
| 置顶/标签/加密/删除/移动 | 列表左滑 → 快捷菜单 | 1 |
| 新建待办 | 待办页下拉 | 1 |
| 完成待办 | 待办页右滑 | 1 |
| 更换提醒色/延后 | 待办页左滑 | 1 |

## 检索与筛选维度

全文（标题/正文/OCR/ASR）· 文件夹 · 标签（字母/数字/图形）· 颜色 · 笔记类型 · 时间范围 —— 可组合筛选；视图在「网格瀑布流 / 紧凑列表」间切换。
