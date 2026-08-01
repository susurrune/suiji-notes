import 'dart:io';

import 'package:flutter/material.dart';

/// 个人头像：显示本地图片（应用目录内路径），未设置时显示占位人形图标。
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.path,
    this.size = 56,
    this.onTap,
  });

  final String? path;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = path == null || path!.isEmpty ? null : File(path!);

    Widget child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
      ),
      child: Icon(
        Icons.person,
        size: size * 0.55,
        color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
      ),
    );

    if (file != null && file.existsSync()) {
      child = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => child,
          ),
        ),
      );
    }

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: child,
    );
  }
}
