import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/state_views.dart';
import '../../models/app_notification.dart';
import 'notifications_controller.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Column(
        children: [
          if (state.offline) OfflineBanner(lastSync: state.lastSync),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(notificationsControllerProvider.notifier).refresh(),
              child: _buildBody(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NotificationsState state) {
    if (state.loading && state.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          MessageView(
            icon: Icons.wifi_off,
            title: 'Could not load notifications',
            subtitle: state.error,
            onRetry: () =>
                ref.read(notificationsControllerProvider.notifier).load(),
          ),
        ],
      );
    }
    if (state.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          const MessageView(
            icon: Icons.notifications_none,
            title: 'No notifications',
            subtitle: 'You are all caught up.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: state.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final note = state.items[i];
        return _NotificationTile(
          note: note,
          onOpen: () => ref
              .read(notificationsControllerProvider.notifier)
              .markRead(note.id),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.note, required this.onOpen});
  final AppNotification note;

  /// Called when the user taps the notification (marks it read).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ts = note.timestamp;
    final when = ts != null
        ? DateFormat('MMM d, y · h:mm a').format(toManila(ts))
        : '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: note.isRead ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconFor(note.type),
                  color: scheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: note.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                          ),
                        ),
                        if (!note.isRead)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (note.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note.body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      when,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type.toUpperCase()) {
      case 'LATE':
        return Icons.schedule;
      case 'ABSENT':
        return Icons.event_busy;
      default:
        return Icons.notifications_active_outlined;
    }
  }
}
