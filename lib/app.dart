import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/providers.dart';
import 'features/home/home_shell.dart';
import 'ui/theme/app_theme.dart';

/// 应用根组件：主题（浅/深/跟随系统）+ 底部导航壳。
class SuijiApp extends ConsumerWidget {
  const SuijiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '随记',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const HomeShell(),
    );
  }
}
