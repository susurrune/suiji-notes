import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/theme/note_colors.dart';
import '../../ui/widgets/app_empty_state.dart';
import '../../ui/widgets/note_card.dart';
import '../editor/editor_screen.dart';

/// 检索输入（防抖写入）。
final searchQueryProvider = StateProvider<String>((ref) => '');
/// 笔记类型筛选。
final searchTypeFilterProvider = StateProvider<BlockType?>((ref) => null);
/// 标签筛选。
final searchTagFilterProvider = StateProvider<String?>((ref) => null);
/// 颜色筛选。
final searchColorFilterProvider = StateProvider<String?>((ref) => null);

/// 检索结果（FTS5，含组合筛选：类型/标签/颜色）。
final searchResultsProvider = FutureProvider<List<Note>>((ref) {
  final q = ref.watch(searchQueryProvider).trim();
  final type = ref.watch(searchTypeFilterProvider);
  final tagId = ref.watch(searchTagFilterProvider);
  final color = ref.watch(searchColorFilterProvider);
  if (q.isEmpty && type == null && tagId == null && color == null) {
    return Future.value(const []);
  }
  return ref
      .watch(searchRepositoryProvider)
      .searchNotes(query: q, type: type, tagId: tagId, color: color);
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _c = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(searchQueryProvider.notifier).state = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _c,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索标题、正文、图片文字、语音…',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: Column(
        children: [
          _TypeFilterRow(),
          const _TagColorFilterRow(),
          const Divider(height: 1),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('搜索出错：$e')),
              data: (items) {
                final hasFilter = ref.watch(searchTypeFilterProvider) != null ||
                    ref.watch(searchTagFilterProvider) != null ||
                    ref.watch(searchColorFilterProvider) != null;
                if (_c.text.trim().isEmpty && !hasFilter) {
                  return const _Hint();
                }
                if (items.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.search_off,
                    title: '没有匹配的笔记',
                    subtitle: '换个关键词或放宽筛选条件试试',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: NoteCard(
                      note: items[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditorScreen(noteId: items[i].id),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeFilterRow extends ConsumerWidget {
  const _TypeFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(searchTypeFilterProvider);
    final choices = <BlockType, (IconData, String)>{
      BlockType.text: (Icons.title, '文本'),
      BlockType.checklist: (Icons.checklist, '清单'),
      BlockType.image: (Icons.image_outlined, '图片'),
      BlockType.voice: (Icons.mic, '语音'),
      BlockType.drawing: (Icons.gesture, '手绘'),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: selected == null,
              onSelected: (_) =>
                  ref.read(searchTypeFilterProvider.notifier).state = null,
            ),
          ),
          for (final e in choices.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(e.value.$1, size: 16),
                label: Text(e.value.$2),
                selected: selected == e.key,
                onSelected: (_) =>
                    ref.read(searchTypeFilterProvider.notifier).state =
                        selected == e.key ? null : e.key,
              ),
            ),
        ],
      ),
    );
  }
}

/// 标签 + 颜色筛选条。
class _TagColorFilterRow extends ConsumerWidget {
  const _TagColorFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsListProvider).value ?? const <Tag>[];
    final selTag = ref.watch(searchTagFilterProvider);
    final selColor = ref.watch(searchColorFilterProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            // 标签筛选
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: const Text('任意标签'),
                selected: selTag == null,
                onSelected: (_) =>
                    ref.read(searchTagFilterProvider.notifier).state = null,
              ),
            ),
            for (final t in tags)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t.name),
                  selected: selTag == t.id,
                  onSelected: (_) => ref
                      .read(searchTagFilterProvider.notifier)
                      .state = selTag == t.id ? null : t.id,
                ),
              ),
            const SizedBox(width: 8),
            // 颜色筛选
            for (final c in NoteColor.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => ref
                      .read(searchColorFilterProvider.notifier)
                      .state = selColor == c.name ? null : c.name,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c == NoteColor.none
                          ? theme.colorScheme.surfaceContainerHighest
                          : noteColorOf(c.name),
                      border: Border.all(
                        color: selColor == c.name
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: selColor == c.name ? 2.5 : 1,
                      ),
                    ),
                    child: selColor == c.name
                        ? Icon(Icons.check,
                            size: 14,
                            color: c == NoteColor.none
                                ? theme.colorScheme.onSurface
                                : Colors.black54)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.search,
      title: '输入关键词，即时检索',
      subtitle: '标题、正文、图片文字、语音转写都能搜到',
    );
  }
}
