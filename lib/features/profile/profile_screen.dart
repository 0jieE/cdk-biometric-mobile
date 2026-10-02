import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_controller.dart';
import '../notifications/fcm_service.dart';
import '../settings/theme_section.dart';
import 'change_password_screen.dart';
import 'change_username_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(authControllerProvider).employee;
    final firebaseReady = ref.watch(firebaseReadyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: employee == null
          ? const MessageView(
              icon: Icons.person_off_outlined,
              title: 'Profile unavailable',
              subtitle: 'Reconnect to load your profile.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ProfileHeader(
                  fullName: employee.fullName,
                  position: employee.position,
                  photoUrl: employee.photoUrl,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.badge_outlined,
                        label: 'Employee No.',
                        value: employee.employeeNo,
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.alternate_email,
                        label: 'Username',
                        value: employee.username.isEmpty
                            ? '—'
                            : employee.username,
                        trailing: IconButton(
                          tooltip: 'Change username',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _changeUsername(context),
                        ),
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.apartment_outlined,
                        label: 'Department',
                        value: employee.department.isEmpty
                            ? '—'
                            : '${employee.department} (${employee.departmentCode})',
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.work_outline,
                        label: 'Position',
                        value: employee.position.isEmpty
                            ? '—'
                            : employee.position,
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.schedule_outlined,
                        label: 'Employment',
                        value: employee.isFulltime ? 'Full-time' : 'Part-time',
                      ),
                      if (employee.dateHired != null) ...[
                        const Divider(height: 1),
                        _InfoRow(
                          icon: Icons.event_available_outlined,
                          label: 'Date hired',
                          value: _formatDate(employee.dateHired!),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Change password'),
                    subtitle: const Text('Update your sign-in password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePassword(context),
                  ),
                ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: ThemeSection(),
                  ),
                ),
                const SizedBox(height: 16),
                _PushStatusTile(enabled: firebaseReady),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: AppTheme.absent,
                    side: const BorderSide(color: AppTheme.absent),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                  onPressed: () => _confirmLogout(context, ref),
                ),
              ],
            ),
    );
  }

  /// `2023-01-15` → `January 15, 2023` (falls back to the raw value).
  static String _formatDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('MMMM d, y').format(d);
  }

  Future<void> _changeUsername(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ChangeUsernameScreen()),
    );
    if (changed != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Username changed to "$changed".')),
      );
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
    if (changed == true) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Password changed.')),
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'This clears your saved session and cached attendance on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({
    required this.fullName,
    required this.position,
    required this.photoUrl,
  });
  final String fullName;
  final String position;
  final String? photoUrl;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  bool _uploading = false;

  /// Bottom sheet: camera or gallery.
  Future<void> _choosePhotoSource() async {
    if (_uploading) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));

    try {
      // Downscale + re-encode as JPEG on the phone: a small upload, and it
      // turns HEIC (which the server rejects) into JPEG.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return; // cancelled
      if (mounted) setState(() => _uploading = true);
      await ref.read(authControllerProvider.notifier).updatePhoto(picked.path);
      say('Profile photo updated.');
    } on ApiException catch (e) {
      say(e.message);
    } on NetworkUnavailable {
      say('Cannot reach the server. Check your internet connection.');
    } catch (_) {
      say('Could not get the photo. Check the camera/gallery permission.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName = widget.fullName;
    final position = widget.position;
    final initials = fullName.isEmpty
        ? '?'
        : fullName
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0])
              .join()
              .toUpperCase();
    final primary = Theme.of(context).colorScheme.primary;
    final photoUrl = widget.photoUrl;

    return Column(
      children: [
        // Purple brand strip with the CDK logo.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient(primary),
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const BrandLogo(size: 34, onLight: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Colegio de Kidapawan',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Employee attendance',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          label: 'Change profile photo',
          child: GestureDetector(
            onTap: _choosePhotoSource,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: primary,
                  // The photo URL changes on every upload, so it doubles as
                  // the cache key; the initials show while loading, offline
                  // with nothing cached, or when there is no photo.
                  foregroundImage: photoUrl == null
                      ? null
                      : CachedNetworkImageProvider(
                          photoUrl,
                          headers: ApiConfig.imageHeaders,
                        ),
                  onForegroundImageError: photoUrl == null ? null : (_, _) {},
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_uploading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: primary,
                      child: const Icon(
                        Icons.photo_camera,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          fullName,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (position.isNotEmpty)
          Text(
            position,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).hintColor,
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      trailing: trailing,
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PushStatusTile extends StatelessWidget {
  const _PushStatusTile({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          enabled
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          color: enabled ? AppTheme.present : Theme.of(context).hintColor,
        ),
        title: const Text('Push notifications'),
        subtitle: Text(
          enabled
              ? 'Enabled — you will be alerted when marked late or absent.'
              : 'Not configured on this build.',
        ),
      ),
    );
  }
}
