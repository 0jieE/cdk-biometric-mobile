import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

/// Appearance controls: accent picker + light/dark toggle. Persists via the
/// theme controller and applies live.
class ThemeSection extends ConsumerWidget {
  const ThemeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    final isDark = settings.mode == ThemeMode.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.palette_outlined),
            const SizedBox(width: 8),
            Text('Theme', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Accent color',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            for (final accent in AppAccent.values)
              _AccentSwatch(
                accent: accent,
                selected: settings.accent == accent,
                onTap: () => controller.setAccent(accent),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
          title: const Text('Dark mode'),
          subtitle: const Text('The app is designed to look great in dark.'),
          value: isDark,
          onChanged: controller.toggleDark,
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });
  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${accent.label} accent',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.seed,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.onSurface : Colors.transparent,
                  width: 3,
                ),
                boxShadow: AppTheme.softShadow,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 22)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(accent.label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
