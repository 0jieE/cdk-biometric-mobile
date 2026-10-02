# CDK Attendance — Employee Mobile App (Phase 3)

Flutter employee-facing app for the **Web-Based Biometric Attendance Monitoring
System with Mobile Integration** (Colegio de Kidapawan).

Employees log in, view their own attendance history + a summary for any **date range**, read
notifications, and receive push alerts when marked **late/absent**. Attendance
is **viewable offline** from a local cache (the paper's "offline data
synchronization" requirement).

This app is **read-only** for attendance — punches come from the biometric
device, not the phone. Admin functions live in the web portal.

---

## Tech stack

| Concern | Package |
|---|---|
| State management | `flutter_riverpod` (Riverpod 3, `Notifier`) |
| HTTP + auth refresh | `dio` (interceptor auto-refreshes JWT on 401) |
| Secure token storage | `flutter_secure_storage` |
| Offline cache | `hive` / `hive_flutter` (manual JSON, no codegen) |
| Navigation + guard | `go_router` |
| Push | `firebase_core` + `firebase_messaging` + `flutter_local_notifications` |
| Dates | `intl` |

---

## Backend contract (DRF API, `../backend`)

Base path `/api/v1/`, JWT (simplejwt), page size 25. Access token lasts 60 min,
refresh token 7 days (not rotated — `/auth/refresh/` returns only `access`).

| Method | Path | Notes |
|---|---|---|
| GET | `/health/` | **public** → `{"status":"ok","service":"attendance-api"}` |
| POST | `/auth/login/` | `{username, password}` → `{access, refresh}` |
| POST | `/auth/refresh/` | `{refresh}` → `{access}` |
| GET | `/me/` | `employee_no, full_name, first_name, last_name, department, department_code, position, date_hired, is_fulltime, employment_type, username, photo_url` (`photo_url` is null when unset; it changes on every upload) |
| POST/PUT | `/me/photo/` | multipart, file field `photo` (JPEG/PNG/WebP ≤ 10 MB, not HEIC) → `{photo_url}`; server shrinks to 512 px |
| POST/PUT/PATCH | `/me/username/` | `{username, current_password}` → `{username}`; lowercased, 3-30 chars `[a-z0-9._-]`; taken/reserved/other-employee-number names → 400 "not available"; shares the 5/min throttle; nobody is signed out |
| POST | `/me/password/` | `{old_password, new_password}` → `{access, refresh}`; throttled 5/min (429); 400 has per-field errors |
| GET | `/attendance/?start=&end=` | **paginated**, newest first, default last 30 days. Two shapes by `employee_type` (see below) |
| GET | `/attendance/summary/?month=YYYY-MM` | `{month, present, late, half_day, absent, overtime_minutes}` — month only; the app doesn't use it (see below) |
| GET | `/notifications/` | **paginated**: `id, title, body, type, is_read, sent_at, created_at` |
| POST | `/notifications/<id>/read/` | marks one of your notifications read (200, or 404 if not yours) |
| POST | `/devices/register/` | `{fcm_token, platform}` → 201 new / 200 existing |

- **Full-time day:** `am`/`pm` `{in,out,status,minutes_late,minutes_undertime}`,
  `overtime_minutes`, `day_status`.
- **Part-time day:** `in`, `out`, `day_status`, `incomplete`, `missing` (`IN`/`OUT`/null).
- `day_status` ∈ `PRESENT | LATE | HALF_DAY | ABSENT` (there is no `ON_TIME`).
- `username` is the employee number lowercased (e.g. `emp-1002`).

Things the app handles:
- **Two time formats.** Attendance is UTC (`…Z`); notifications carry `+08:00`.
  Models parse both to exact instants and screens display them in **Asia/Manila
  (UTC+8)** via `core/time.dart`, regardless of the phone's timezone.
- **Errors:** 400 bad range/month/platform, 401 no/invalid token (→ refresh),
  403 admin account on an employee endpoint, 404 out-of-range page. Non-2xx
  responses throw in dio, so the auth interceptor sees 401s.
- **Attendance filter = date range.** The summary (present / late / half-day /
  absent / overtime) is computed from the days in the selected range, so it
  always matches what is listed. Default range: 1st of this month → today.
- **Profile photo:** tap the avatar → camera or gallery. `image_picker` downsizes
  to ≤1024 px JPEG (which also turns HEIC into JPEG) before upload; the image is
  shown with `cached_network_image` keyed by `photo_url`, so it also displays
  offline. Initials are shown when there is no photo.
- **Change username:** Profile → the pencil next to *Username* (needs the current
  password). The same format rule is checked in the app before sending; server
  errors appear under the `username` / `current_password` field. The login
  screen takes the username (which starts as the lowercased employee number).
- **Summary card:** two labelled rows of identical tiles. *Days*: Present /
  Half-day / Absent. *Time*: Late / Undertime / Total lost / Overtime (total
  minutes, e.g. `4h 6m`). *Present* means full days attended, on time or late
  (the backend's LATE status is any day with a late session, by any number of
  minutes — there is no 24-hour rule — so it is folded into Present rather than
  shown as a second "late" number). Lateness is shown only as time. The minutes
  are summed from each day's `late_minutes` / `undertime_minutes` /
  `overtime_minutes`; *Total lost* = late + undertime (the backend's
  `lost_minutes`). They match `/attendance/summary/` for a whole month and work
  for any range. A day with one late and one absent session is a Half-day; its
  late minutes are still included in *Time · Late*.
- **Change password:** Profile → *Change password*. Server messages appear under
  the matching field (`old_password` / `new_password`); 429 shows a
  "too many attempts" message. On success the new access/refresh pair replaces
  the stored tokens (all older tokens stop working). If a refresh later fails
  with `code: password_changed` (changed on another device / by an admin), the
  app returns to login with an explanatory message.
- **Opening a notification** (tap) marks it read: instantly in the app, then via
  `POST /notifications/<id>/read/`.
- **Invalid `start`/`end` are ignored by the server** (default range returned),
  but the app only ever sends dates chosen in its date-range picker.
- **CORS** only matters for Flutter web; native apps ignore it.
- Every request sends `ngrok-skip-browser-warning: true` (ngrok free tier can
  otherwise serve an HTML warning page).

## Server URL (fixed)

The app talks to one fixed backend: **`https://usage-angles-emporium.ngrok-free.dev`**
(`ApiConfig.defaultBaseUrl`). There is no in-app server setting. If the ngrok
URL changes, edit that constant or build with an override:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # e.g. emulator → local backend
```

Cleartext HTTP is enabled in the Android manifest (`usesCleartextTraffic=true`)
for LAN dev servers; the public URL is HTTPS.

---

## Run

```bash
flutter pub get

# Connects to the public ngrok backend by default:
flutter run

# …or override the URL for this run:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000        # emulator
flutter run --dart-define=API_BASE_URL=https://other.ngrok-free.dev
```

Build a debug APK:

```bash
flutter build apk --debug
# optionally: --dart-define=API_BASE_URL=https://other.ngrok-free.dev
```

### Seeded employee login

Run `python manage.py seed_data` on the backend, then log in with:

```
Employee number:  emp-1002     (username = employee_no, lowercased)
Password:         employee12345
```

Employees `emp-1001` … `emp-1008` all use the same password (seed data; the
public server currently has `emp-1002`).

---

## Offline behaviour

Every successful fetch is written to Hive, keyed by the selected date range. On a network failure
the screen loads the last-synced data from cache and shows a subtle
**"Offline — showing saved data"** banner with the last-sync time.
Pull-to-refresh re-fetches when back online. Logout clears tokens **and** cache.

---

## Firebase / FCM push (Phase 7 — configured, Android)

**Configured** for Firebase project **`biometric-attendance-25729`** via
`flutterfire configure`. Generated, committed files:
- `lib/firebase_options.dart` — `DefaultFirebaseOptions.currentPlatform`
  (used by `Firebase.initializeApp` in `main.dart` and the background handler).
- `android/app/google-services.json` — safe to commit (client config, not a
  secret). The Google Services Gradle plugin auto-applies when this file exists
  (see `android/app/build.gradle.kts`).

The app still **runs fine without Firebase** — `Firebase.initializeApp` is
guarded, so a missing/unreachable config just skips push (Profile shows
"Push notifications: Not configured").

Runtime flow (already wired in `features/notifications/fcm_service.dart`):
- Requests notification permission (Android 13+ `POST_NOTIFICATIONS`).
- After login, gets the FCM token and POSTs it to `/api/v1/devices/register/`
  with `platform: ANDROID`; re-registers on `onTokenRefresh`.
- **Foreground** (`onMessage`) → shown via `flutter_local_notifications`
  (channel `attendance_alerts`).
- **Background/terminated** → top-level `@pragma('vm:entry-point')`
  `firebaseBackgroundHandler`; the OS shows the tray notification.
- **Tap** (`onMessageOpenedApp` / `getInitialMessage`) → opens the
  **Notifications** tab.

### To re-run FlutterFire (e.g. new machine / different project)
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=biometric-attendance-25729 \
  --platforms=android --android-package-name=ph.edu.ckc.biometric_mobile
```

### Backend side (done in the `backend/` session — Phase 7 PART C)
Generate a **service-account private key** (Firebase Console → Project Settings
→ Service Accounts), save to `backend/secrets/firebase-service-account.json`
(**gitignored — it is a secret**), set `FIREBASE_CREDENTIALS` to its in-container
path, then `docker compose restart web celery_worker`. Test with
`python manage.py send_test_push <employee_no>`.

*(iOS push is intentionally skipped — needs a paid Apple Developer account + APNs.)*

---

## Project structure

```
lib/
  main.dart                      # bootstrap: Hive, graceful Firebase, providers
  core/
    config/     api_config.dart  # runtime base URL resolution + endpoints
    network/    api_client.dart, auth_interceptor.dart  # dio + 401 refresh
    storage/    secure_token_store.dart, cache_store.dart, settings_store.dart
    router/     app_router.dart  # go_router + auth guard + empty-URL guard
    theme/      app_theme.dart    # Material 3, CDK colors
    widgets/    offline_banner.dart, state_views.dart
    time.dart                    # parse API instants, show in Asia/Manila
    providers.dart               # apiBaseUrlProvider, apiClientProvider, stores
  features/
    auth/          login_screen, auth_controller, auth_repository, auth_state
    home/          home_shell (bottom nav), splash_screen
    attendance/    attendance_screen, controller, repository, widgets/status_chip
    notifications/ notifications_screen, controller, repository, fcm_service
    settings/      theme_section                # accent + dark mode (in Profile)
    profile/       profile_screen
  models/          employee, attendance_day, monthly_summary, app_notification
test/
  auth_controller_test.dart          # login stores tokens; failed refresh → logout
  attendance_cache_test.dart         # network error → cached data
  attendance_list_widget_test.dart   # renders full-time / part-time cards
  api_client_refresh_test.dart       # ngrok header, 4xx mapping, Manila time
  profile_test.dart                  # photo upload, change password, password_changed logout
  attendance_range_test.dart         # date-range filter + derived summary
  notifications_mark_read_test.dart  # opening a notification marks it read
  helpers.dart                       # in-memory stores + fake dio adapter
```

---

## Tests

```bash
flutter test
```

Covers: login stores tokens & a failed refresh forces logout; the attendance
provider falls back to cache on network error; full-time/part-time cards render;
base-URL resolution and Test Connection; ngrok header, error mapping and
UTC → Manila conversion.
