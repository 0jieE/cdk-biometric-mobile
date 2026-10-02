import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Subtle banner shown when a screen is displaying cached data because the
/// backend was unreachable.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.lastSync});

  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final synced = lastSync != null
        ? 'Last synced ${DateFormat('MMM d, h:mm a').format(lastSync!)}'
        : null;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offline — showing saved data',
                    style: TextStyle(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    synced ?? 'Check your internet connection',
                    style: TextStyle(
                      color: scheme.onTertiaryContainer.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
