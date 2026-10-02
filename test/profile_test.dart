import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/core/config/api_config.dart';
import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/network/auth_interceptor.dart';
import 'package:biometric_mobile/features/auth/auth_controller.dart';
import 'package:biometric_mobile/features/auth/auth_repository.dart';
import 'package:biometric_mobile/features/profile/change_password_screen.dart';
import 'package:biometric_mobile/features/profile/change_username_screen.dart';
import 'package:biometric_mobile/models/employee.dart';

import 'helpers.dart';

const _root = 'http://test.local/api/v1';

AuthRepository _repo(
  InMemoryTokenStore tokens,
  FakeResponse Function(RequestOptions) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: _root))
    ..httpClientAdapter = FakeHttpAdapter(handler);
  final client = ApiClient(
    apiRoot: _root,
    tokenStore: tokens,
    onForceLogout: () async {},
    dio: dio,
  );
  return AuthRepository(apiClient: client, tokenStore: tokens);
}

/// Best-effort: on Windows the fake adapter can leave the picked file open.
void _cleanUp(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // temp dir; the OS will collect it
  }
}

void main() {
  group('Employee', () {
    test(
      'parses photo_url (null when there is no photo) and round-trips it',
      () {
        final withPhoto = Employee.fromJson({
          'employee_no': 'EMP-1002',
          'photo_url': 'https://x.example/media/employees/emp-1002-ab12.jpg',
        });
        expect(withPhoto.photoUrl, endsWith('emp-1002-ab12.jpg'));
        expect(
          Employee.fromJson(withPhoto.toJson()).photoUrl,
          withPhoto.photoUrl,
        );

        expect(Employee.fromJson({'employee_no': 'EMP-1'}).photoUrl, isNull);
      },
    );

    test('copyWith swaps only the photo', () {
      const e = Employee(
        employeeNo: 'EMP-1',
        fullName: 'A B',
        firstName: 'A',
        lastName: 'B',
        department: 'HR',
        departmentCode: 'HR',
        position: 'X',
      );
      final updated = e.copyWith(photoUrl: 'https://x/p.jpg');
      expect(updated.photoUrl, 'https://x/p.jpg');
      expect(updated.fullName, 'A B');
    });
  });

  group('Photo upload', () {
    test(
      'posts multipart with a `photo` file and returns the new URL',
      () async {
        final dir = Directory.systemTemp.createTempSync('photo_test');
        addTearDown(() => _cleanUp(dir));
        final file = File('${dir.path}/me.jpg')..writeAsBytesSync([1, 2, 3, 4]);

        RequestOptions? seen;
        final repo = _repo(InMemoryTokenStore(), (opts) {
          seen = opts;
          return const FakeResponse(200, {'photo_url': 'https://x/new.jpg'});
        });

        final url = await repo.uploadPhoto(file.path);

        expect(url, 'https://x/new.jpg');
        expect(seen!.method, 'POST');
        expect(seen!.path, ApiConfig.mePhoto);
        final form = seen!.data as FormData;
        expect(form.files.single.key, 'photo');
        expect(form.files.single.value.filename, 'me.jpg');
        // Must not go out as application/json.
        expect(
          seen!.headers['content-type'].toString(),
          startsWith('multipart/form-data'),
        );
      },
    );

    test('a rejected image surfaces the server message', () async {
      final dir = Directory.systemTemp.createTempSync('photo_test');
      addTearDown(() => _cleanUp(dir));
      final file = File('${dir.path}/bad.jpg')..writeAsBytesSync([0]);
      final repo = _repo(
        InMemoryTokenStore(),
        (_) => const FakeResponse(400, {
          'photo': ['Upload a valid JPEG, PNG or WebP image.'],
        }),
      );

      await expectLater(
        repo.uploadPhoto(file.path),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Upload a valid JPEG, PNG or WebP image.',
          ),
        ),
      );
    });
  });

  group('Change password', () {
    test('success replaces the stored tokens with the new pair', () async {
      final tokens = InMemoryTokenStore()
        ..access = 'old-access'
        ..refresh = 'old-refresh';
      Object? body;
      final repo = _repo(tokens, (opts) {
        body = opts.data;
        return const FakeResponse(200, {
          'detail': 'password changed',
          'access': 'new-access',
          'refresh': 'new-refresh',
        });
      });

      await repo.changePassword(
        oldPassword: 'old-pw',
        newPassword: 'New-pw-123',
      );

      expect(body, {'old_password': 'old-pw', 'new_password': 'New-pw-123'});
      expect(tokens.access, 'new-access');
      expect(tokens.refresh, 'new-refresh');
    });

    test('400 exposes per-field messages and keeps the old tokens', () async {
      final tokens = InMemoryTokenStore()
        ..access = 'a'
        ..refresh = 'r';
      final repo = _repo(
        tokens,
        (_) => const FakeResponse(400, {
          'new_password': [
            'This password is too short.',
            'This password is too common.',
          ],
        }),
      );

      try {
        await repo.changePassword(oldPassword: 'x', newPassword: '123');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 400);
        expect(
          e.fieldErrors['new_password'],
          'This password is too short.\nThis password is too common.',
        );
        expect(e.fieldErrors.containsKey('old_password'), isFalse);
      }
      expect(tokens.access, 'a');
      expect(tokens.refresh, 'r');
    });

    test(
      'a wrong current password is a 400 (not a session-ending 401)',
      () async {
        var forcedOut = false;
        final tokens = InMemoryTokenStore()
          ..access = 'a'
          ..refresh = 'r';
        final dio = Dio(BaseOptions(baseUrl: _root))
          ..httpClientAdapter = FakeHttpAdapter(
            (_) => const FakeResponse(400, {
              'old_password': ['Incorrect password.'],
            }),
          );
        final client = ApiClient(
          apiRoot: _root,
          tokenStore: tokens,
          onForceLogout: () async => forcedOut = true,
          dio: dio,
        );
        final repo = AuthRepository(apiClient: client, tokenStore: tokens);

        await expectLater(
          repo.changePassword(oldPassword: 'nope', newPassword: 'New-pw-123'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.fieldErrors['old_password'],
              'old_password',
              'Incorrect password.',
            ),
          ),
        );
        expect(forcedOut, isFalse);
        expect(tokens.refresh, 'r');
      },
    );

    test('429 (throttled) gets a friendly message', () async {
      final repo = _repo(
        InMemoryTokenStore(),
        (_) => const FakeResponse(429, {
          'detail': 'Request was throttled. Expected available in 41 seconds.',
        }),
      );
      await expectLater(
        repo.changePassword(oldPassword: 'a', newPassword: 'b'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 429)
              .having(
                (e) => e.message,
                'message',
                contains('Too many attempts'),
              ),
        ),
      );
    });
  });

  group('Session ended by a password change elsewhere', () {
    Future<({bool changed, bool forced})> runRefresh(
      FakeResponse refreshResponse,
    ) async {
      var changed = false, forced = false;
      final tokens = InMemoryTokenStore()
        ..access = 'stale'
        ..refresh = 'old-refresh';
      final refreshDio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter((_) => refreshResponse);
      final interceptor = AuthInterceptor(
        tokenStore: tokens,
        onForceLogout: () async => forced = true,
        onPasswordChanged: () async => changed = true,
        refreshDio: refreshDio,
      );
      final dio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter(
          (_) => const FakeResponse(401, {'code': 'token_not_valid'}),
        )
        ..interceptors.add(interceptor);
      await expectLater(dio.get(ApiConfig.me), throwsA(isA<DioException>()));
      expect(await tokens.readRefresh(), isNull);
      return (changed: changed, forced: forced);
    }

    test('refresh 401 code=password_changed → onPasswordChanged', () async {
      final r = await runRefresh(
        const FakeResponse(401, {
          'detail': "The user's password has been changed.",
          'code': 'password_changed',
        }),
      );
      expect(r.changed, isTrue);
      expect(r.forced, isFalse);
    });

    test('any other refresh failure → plain onForceLogout', () async {
      final r = await runRefresh(
        const FakeResponse(401, {'code': 'token_not_valid'}),
      );
      expect(r.changed, isFalse);
      expect(r.forced, isTrue);
    });
  });

  group('ChangePasswordScreen', () {
    Widget host(AuthRepository repo) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ChangePasswordScreen()),
    );

    Future<void> fill(
      WidgetTester tester, {
      String old = 'old-pass',
      String next = 'New-pass-123',
      String confirm = 'New-pass-123',
    }) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), old);
      await tester.enterText(fields.at(1), next);
      await tester.enterText(fields.at(2), confirm);
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
    }

    testWidgets('mismatched confirmation is caught before any request', (
      tester,
    ) async {
      var requests = 0;
      final repo = _repo(InMemoryTokenStore(), (_) {
        requests++;
        return const FakeResponse(200, {});
      });
      await tester.pumpWidget(host(repo));

      await fill(tester, confirm: 'different');

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(requests, 0);
    });

    testWidgets('server field errors appear under the matching field', (
      tester,
    ) async {
      final repo = _repo(
        InMemoryTokenStore(),
        (_) => const FakeResponse(400, {
          'new_password': ['This password is too common.'],
        }),
      );
      await tester.pumpWidget(host(repo));

      await fill(tester);

      expect(find.text('This password is too common.'), findsOneWidget);
      expect(find.text('Incorrect password.'), findsNothing);
    });

    testWidgets('a throttled request shows a banner message', (tester) async {
      final repo = _repo(
        InMemoryTokenStore(),
        (_) => const FakeResponse(429, {'detail': 'Request was throttled.'}),
      );
      await tester.pumpWidget(host(repo));

      await fill(tester);

      expect(find.textContaining('Too many attempts'), findsOneWidget);
    });
  });

  group('Change username', () {
    test(
      'POSTs username + current password and returns the stored name',
      () async {
        Object? body;
        String? path;
        final repo = _repo(InMemoryTokenStore(), (opts) {
          body = opts.data;
          path = opts.path;
          return const FakeResponse(200, {'username': 'jose.reyes'});
        });

        final stored = await repo.changeUsername(
          username: 'Jose.Reyes',
          currentPassword: 'pw',
        );

        expect(stored, 'jose.reyes');
        expect(path, ApiConfig.meUsername);
        expect(body, {'username': 'Jose.Reyes', 'current_password': 'pw'});
      },
    );

    test(
      '400 exposes field errors for username and current_password',
      () async {
        final repo = _repo(
          InMemoryTokenStore(),
          (_) => const FakeResponse(400, {
            'username': ['This username is not available.'],
            'current_password': ['Incorrect password.'],
          }),
        );
        await expectLater(
          repo.changeUsername(username: 'admin', currentPassword: 'x'),
          throwsA(
            isA<ApiException>()
                .having(
                  (e) => e.fieldErrors['username'],
                  'username',
                  'This username is not available.',
                )
                .having(
                  (e) => e.fieldErrors['current_password'],
                  'password',
                  'Incorrect password.',
                ),
          ),
        );
      },
    );

    test('Employee parses and copies the username', () {
      final e = Employee.fromJson({
        'employee_no': 'EMP-1',
        'username': 'emp-1',
      });
      expect(e.username, 'emp-1');
      expect(e.copyWith(username: 'jose').username, 'jose');
      expect(Employee.fromJson(e.toJson()).username, 'emp-1');
    });

    Widget host(AuthRepository repo, void Function(String?) onResult) =>
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async => onResult(
                  await Navigator.of(ctx).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const ChangeUsernameScreen(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester, String name, String pw) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), name);
      await tester.enterText(fields.at(1), pw);
      await tester.tap(find.widgetWithText(FilledButton, 'Change username'));
      await tester.pumpAndSettle();
    }

    testWidgets('a malformed name is caught before any request', (
      tester,
    ) async {
      var requests = 0;
      final repo = _repo(InMemoryTokenStore(), (_) {
        requests++;
        return const FakeResponse(200, {'username': 'x'});
      });
      await tester.pumpWidget(host(repo, (_) {}));
      await open(tester);

      await submit(tester, 'a b!', 'pw');

      expect(find.textContaining('Use 3-30 characters'), findsOneWidget);
      expect(requests, 0);
    });

    testWidgets('server errors show under the right field', (tester) async {
      final repo = _repo(
        InMemoryTokenStore(),
        (_) => const FakeResponse(400, {
          'username': ['This username is not available.'],
        }),
      );
      await tester.pumpWidget(host(repo, (_) {}));
      await open(tester);

      await submit(tester, 'taken.name', 'pw');

      expect(find.text('This username is not available.'), findsOneWidget);
      expect(find.byType(ChangeUsernameScreen), findsOneWidget);
    });

    testWidgets('success pops with the lowercased username', (tester) async {
      String? result;
      final repo = _repo(InMemoryTokenStore(), (opts) {
        expect((opts.data as Map)['username'], 'jose.reyes');
        return const FakeResponse(200, {'username': 'jose.reyes'});
      });
      await tester.pumpWidget(host(repo, (r) => result = r));
      await open(tester);

      await submit(tester, '  Jose.Reyes ', 'pw');

      expect(result, 'jose.reyes');
      expect(find.byType(ChangeUsernameScreen), findsNothing);
    });
  });
}
