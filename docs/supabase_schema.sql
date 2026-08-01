-- 随记 · Supabase 云同步建表脚本
-- 在 Supabase 项目 → SQL Editor 中执行一次即可。
-- 表名/列名与客户端 SyncService 严格对应，请勿改名。

-- 笔记（内容块序列化为 content_json，按整篇同步）
create table if not exists notes_sync (
  id          text primary key,
  title       text not null default '',
  preview     text not null default '',
  folder_id   text,
  color       text,
  pinned      boolean not null default false,
  important   integer not null default 0,
  encrypted   boolean not null default false,
  archived    boolean not null default false,
  trash_time  timestamptz,
  reminder_at timestamptz,
  created_at  timestamptz not null,
  updated_at  timestamptz not null,
  deleted     boolean not null default false,
  content_json text not null default '[]'
);

-- 文件夹
create table if not exists folders_sync (
  id         text primary key,
  name       text not null,
  parent_id  text,
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted    boolean not null default false
);

-- 标签
create table if not exists tags_sync (
  id         text primary key,
  name       text not null,
  kind       text not null default 'alpha',
  created_at timestamptz not null,
  deleted    boolean not null default false
);

-- 笔记-标签关系
create table if not exists note_tags_sync (
  note_id text not null,
  tag_id  text not null,
  primary key (note_id, tag_id)
);

-- 行级安全：仅登录用户可读写自己的数据
alter table notes_sync     enable row level security;
alter table folders_sync   enable row level security;
alter table tags_sync      enable row level security;
alter table note_tags_sync enable row level security;

create policy "own_notes" on notes_sync
  for all using (auth.uid() is not null) with check (auth.uid() is not null);
create policy "own_folders" on folders_sync
  for all using (auth.uid() is not null) with check (auth.uid() is not null);
create policy "own_tags" on tags_sync
  for all using (auth.uid() is not null) with check (auth.uid() is not null);
create policy "own_note_tags" on note_tags_sync
  for all using (auth.uid() is not null) with check (auth.uid() is not null);

-- 媒体存储桶（图片/语音/手绘上传）
insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

create policy "media_own" on storage.objects
  for all using (bucket_id = 'media' and auth.uid() is not null)
  with check (bucket_id = 'media' and auth.uid() is not null);
