/// core 层统一出口。功能模块只需 `import '../core/core.dart'`。
///
/// 用途：把领域模型、数据库与仓库的依赖方向收敛为「功能层 -> core」，
/// 避免功能层直接 import drift 细节。新增仓库/模块时在此追加导出。
library;

export 'domain/block_data.dart';
export 'domain/enums.dart';

// 数据类与 companion 均由 drift 生成于 database.g.dart（database.dart 的 part）。
export 'data/database/database.dart'
    show
        AppDatabase,
        Note,
        Block,
        Folder,
        Tag,
        NoteTag,
        MediaItem,
        ChangeLogEntry,
        Profile,
        FoldersCompanion,
        TagsCompanion,
        NoteTagsCompanion,
        NotesCompanion,
        BlocksCompanion,
        MediaItemsCompanion,
        ChangeLogsCompanion,
        ProfilesCompanion;

export 'data/database/tables.dart' show FtsSchema;
export 'data/repositories/folder_repository.dart';
export 'data/repositories/media_repository.dart';
export 'data/repositories/note_repository.dart';
export 'data/repositories/profile_repository.dart';
export 'data/repositories/search_repository.dart';
export 'data/repositories/tag_repository.dart';
export 'search/tokenizer.dart';
export 'security/secret_service.dart';
export 'utils/date_format.dart';
