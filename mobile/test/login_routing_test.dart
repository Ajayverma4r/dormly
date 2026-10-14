// Post-login routing: runs the real completeLogin / restoreSession /
// switchWorkspace and repositories against a fake server, so every
// decision comes from server-shaped workspace and tenancy data.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dormly/core/network/api_client.dart';
import 'package:dormly/core/storage/app_prefs.dart';
import 'package:dormly/core/storage/auth_storage.dart';
import 'package:dormly/features/auth/domain/user_profile.dart';
import 'package:dormly/features/auth/domain/workspace_resolver.dart';
import 'package:dormly/features/auth/presentation/login_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'user-1';

Map<String, dynamic> _owner(String id, int properties) => {
      'type': 'organization',
      'id': id,
      'role': 'owner',
      'label': 'Org $id',
      'propertyCount': properties,
    };

Map<String, dynamic> _tenant(String id) => {
      'type': 'tenancy',
      'id': id,
      'role': 'tenant',
      'label': 'Sky Hostel — Room 101',
      'propertyId': 'prop-of-$id',
    };

/// Answers the auth endpoints the way the backend does, and only lets the
/// user select workspaces it currently lists.
class _FakeServer implements HttpClientAdapter {
  List<Map<String, dynamic>> workspaces;
  Map<String, int> tenancies;
  final Map<String, List<Map<String, dynamic>>> propertiesByOrg;
  List<Map<String, dynamic>> invitations;
  final List<String> calls = [];
  String? selected;

  /// Simulates membership revoked between listing and selecting.
  bool rejectSelection = false;

  _FakeServer({
    required this.workspaces,
    this.tenancies = const {},
    this.propertiesByOrg = const {},
    this.invitations = const [],
  });

  int get ensureOrgCalls =>
      calls.where((c) => c == 'POST /v1/auth/ensure-organization').length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    calls.add('${options.method} $path');
    ResponseBody ok(Object data) => ResponseBody.fromString(
          jsonEncode({'data': data}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    switch ('${options.method} $path') {
      case 'GET /v1/invitations':
        return ok(invitations);
      case 'GET /v1/auth/contexts':
        return ok(workspaces);
      case 'GET /v1/auth/me':
        return ok({
          'id': _userId,
          'phone': '+919000000001',
          'name': 'Asha',
          'profileComplete': true,
          'propertyCount': 0,
          'tenancies': {
            'active': tenancies['active'] ?? 0,
            'pending': tenancies['pending'] ?? 0,
            'ended': tenancies['ended'] ?? 0,
          },
        });
      case 'POST /v1/auth/contexts/select':
        final body = options.data as Map;
        final match = workspaces.where(
          (w) => w['type'] == body['contextType'] && w['id'] == body['contextId'],
        );
        if (match.isEmpty || rejectSelection) {
          return ResponseBody.fromString('{"error":"forbidden"}', 403);
        }
        selected = workspaceKey(match.first);
        return ok({'accessToken': 'scoped', 'context': match.first});
      case 'POST /v1/auth/ensure-organization':
        final org = _owner('org-new', 0);
        workspaces = [...workspaces, org];
        selected = workspaceKey(org);
        return ok({'accessToken': 'scoped', 'context': org, 'organizationId': 'org-new'});
      case 'GET /v1/properties':
        final org = options.queryParameters['organizationId'] as String?;
        return ok(propertiesByOrg[org] ?? <Object>[]);
    }
    if (options.method == 'GET' && path.startsWith('/v1/properties/')) {
      final id = path.substring('/v1/properties/'.length);
      final scoped = workspaces.any(
        (w) => workspaceKey(w) == selected && w['propertyId'] == id,
      );
      if (!scoped) return ResponseBody.fromString('{"error":"forbidden"}', 403);
      return ok({'id': id, 'name': 'Sky Hostel'});
    }
    return ResponseBody.fromString('{"error":"not found"}', 404);
  }

  @override
  void close({bool force = false}) {}
}

class _Harness {
  final _FakeServer server;
  late final GoRouter router;
  late BuildContext context;
  late WidgetRef ref;
  List<Map<String, dynamic>>? pickerOptions;

  _Harness(this.server);

  String get location =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  Future<void> pump(WidgetTester tester) async {
    final client = ApiClient();
    client.dio.httpClientAdapter = server;
    Widget page(String name) => Scaffold(body: Text('route:$name'));
    router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, __) => Scaffold(
            body: Consumer(builder: (c, r, _) {
              context = c;
              ref = r;
              return const Text('start');
            }),
          ),
        ),
        for (final path in [
          '/tenant/dashboard',
          '/tenant/unavailable',
          '/onboarding/welcome',
          '/onboarding/profile',
          '/invitations',
          '/home',
        ])
          GoRoute(path: path, builder: (_, __) => page(path)),
        GoRoute(
          path: '/select-context',
          builder: (_, s) {
            pickerOptions = s.extra as List<Map<String, dynamic>>;
            return page('/select-context');
          },
        ),
        GoRoute(
          path: '/property/:id',
          builder: (_, s) => page('/property/${s.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp.router(routerConfig: router),
    ));
  }

  /// Runs [action] from a live start page, as the real screens call these
  /// helpers from a mounted widget.
  Future<void> run(WidgetTester tester, Future<void> Function() action) async {
    if (location != '/start') {
      router.go('/start');
      await tester.pumpAndSettle();
    }
    await tester.runAsync(action);
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester) =>
      run(tester, () => completeLogin(context, ref));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      AuthStorage.accessTokenKey: 'token',
      AuthStorage.refreshTokenKey: 'refresh',
      AuthStorage.userIdKey: _userId,
    });
  });

  testWidgets('tenant login opens the tenant dashboard, never property setup',
      (tester) async {
    // Includes the empty owner workspace older logins created for tenants.
    final server = _FakeServer(
      workspaces: [_owner('org-auto', 0), _tenant('ten-1')],
      tenancies: {'active': 1},
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);

    expect(h.location, '/tenant/dashboard');
    expect(server.selected, 'tenancy:ten-1');
    expect(server.ensureOrgCalls, 0);
    expect(server.calls, isNot(contains('GET /v1/properties')));
  });

  testWidgets('existing owner opens their property dashboard', (tester) async {
    final server = _FakeServer(
      workspaces: [_owner('org-1', 2)],
      propertiesByOrg: {
        'org-1': [
          {'id': 'p1', 'name': 'Sky Hostel'},
          {'id': 'p2', 'name': 'Lake PG'},
        ],
      },
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);

    expect(h.location, '/property/p1');
    expect(server.selected, 'organization:org-1');
    expect(server.ensureOrgCalls, 0);
  });

  for (final role in ['manager', 'staff']) {
    testWidgets('accepted $role opens only their assigned property',
        (tester) async {
      final server = _FakeServer(workspaces: [
        {
          'type': 'organization',
          'id': 'prop-7',
          'role': role,
          'label': 'Sky Hostel',
          'propertyId': 'prop-7',
        },
      ]);
      final h = _Harness(server);
      await h.pump(tester);
      await h.login(tester);

      expect(h.location, '/property/prop-7');
      expect(server.selected, 'organization:prop-7');
      expect(server.ensureOrgCalls, 0);
    });
  }

  testWidgets('a pending team invitation is shown before any workspace opens',
      (tester) async {
    final server = _FakeServer(
      workspaces: [_tenant('ten-1')],
      tenancies: {'active': 1},
      invitations: [
        {'id': 'inv-1', 'role': 'manager', 'property_name': 'Sky Hostel'},
      ],
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);

    expect(h.location, '/invitations');
    expect(server.selected, isNull);
  });

  testWidgets('new owner with no memberships goes to property setup',
      (tester) async {
    final server = _FakeServer(workspaces: []);
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);

    expect(server.ensureOrgCalls, 1);
    expect(h.location, '/onboarding/welcome');
  });

  testWidgets('owner whose workspace has no property yet goes to setup',
      (tester) async {
    final server = _FakeServer(workspaces: [_owner('org-1', 0)]);
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);

    expect(server.selected, 'organization:org-1');
    expect(server.ensureOrgCalls, 0);
    expect(h.location, '/onboarding/welcome');
  });

  for (final status in ['pending', 'ended']) {
    testWidgets('$status tenancy gets no dashboard and no owner setup',
        (tester) async {
      final server = _FakeServer(
        workspaces: [_owner('org-auto', 0)],
        tenancies: {status: 1},
      );
      final h = _Harness(server);
      await h.pump(tester);
      await h.login(tester);

      expect(h.location, '/tenant/unavailable');
      expect(server.selected, isNull);
      expect(server.ensureOrgCalls, 0);
      expect(server.calls, isNot(contains('GET /v1/properties')));
    });
  }

  testWidgets('a tenancy the server no longer lists cannot be selected',
      (tester) async {
    final server = _FakeServer(
      workspaces: [_tenant('ten-1')],
      tenancies: {'active': 1},
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(h.location, '/tenant/dashboard');

    // Tenancy ended on the server; the remembered workspace is not reused.
    server.workspaces = [];
    server.tenancies = {'ended': 1};
    server.selected = null;
    await h.login(tester);
    expect(h.location, '/tenant/unavailable');
    expect(server.selected, isNull);
  });

  testWidgets('tenant + owner can switch workspaces; the choice survives restart',
      (tester) async {
    final server = _FakeServer(
      workspaces: [_owner('org-1', 1), _tenant('ten-1')],
      tenancies: {'active': 1},
      propertiesByOrg: {
        'org-1': [
          {'id': 'p1', 'name': 'Sky Hostel'},
        ],
      },
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(h.location, '/property/p1');

    await h.run(tester, () => switchWorkspace(h.context, h.ref));
    expect(server.selected, 'tenancy:ten-1');
    expect(h.location, '/tenant/dashboard');
    expect(await AppPrefs.lastWorkspace(_userId), 'tenancy:ten-1');

    // App restart: a fresh app restores the session and the last workspace.
    final restarted = _Harness(server);
    await restarted.pump(tester);
    await restarted.run(
      tester,
      () => restoreSession(restarted.context, restarted.ref),
    );
    expect(restarted.location, '/tenant/dashboard');

    await restarted.run(
      tester,
      () => switchWorkspace(restarted.context, restarted.ref),
    );
    expect(server.selected, 'organization:org-1');
    expect(restarted.location, '/property/p1');
  });

  testWidgets('admin with properties opens the organization dashboard',
      (tester) async {
    final server = _FakeServer(
      workspaces: [
        {..._owner('org-1', 1), 'role': 'admin'},
      ],
      propertiesByOrg: {
        'org-1': [
          {'id': 'p1', 'name': 'Sky Hostel'},
        ],
      },
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(h.location, '/property/p1');
    expect(server.selected, 'organization:org-1');
  });

  testWidgets('staff + tenant: staff first, and both directions switch',
      (tester) async {
    final staffWorkspace = {
      'type': 'organization',
      'id': 'prop-7',
      'role': 'staff',
      'label': 'Lake PG',
      'propertyId': 'prop-7',
    };
    final server = _FakeServer(
      workspaces: [_tenant('ten-1'), staffWorkspace],
      tenancies: {'active': 1},
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(h.location, '/property/prop-7');

    await h.run(tester, () => switchWorkspace(h.context, h.ref));
    expect(server.selected, 'tenancy:ten-1');
    expect(h.location, '/tenant/dashboard');

    await h.run(tester, () => switchWorkspace(h.context, h.ref));
    expect(server.selected, 'organization:prop-7');
    expect(h.location, '/property/prop-7');
  });

  testWidgets('with several other workspaces the user picks from the server list',
      (tester) async {
    final server = _FakeServer(
      workspaces: [
        _tenant('ten-1'),
        _owner('org-1', 1),
        {
          'type': 'organization',
          'id': 'prop-7',
          'role': 'manager',
          'label': 'Lake PG',
          'propertyId': 'prop-7',
        },
        _owner('org-legacy', 0),
      ],
      tenancies: {'active': 1},
      propertiesByOrg: {
        'org-1': [
          {'id': 'p1', 'name': 'Sky Hostel'},
        ],
      },
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(server.selected, 'organization:org-1');

    await h.run(tester, () => switchWorkspace(h.context, h.ref));
    expect(h.location, '/select-context');
    expect(h.pickerOptions?.map(workspaceKey), [
      'organization:prop-7',
      'tenancy:ten-1',
    ]);
  });

  testWidgets('a remembered empty owner workspace never outranks an active tenancy',
      (tester) async {
    await AppPrefs.setLastWorkspace(_userId, 'organization', 'org-auto');
    final server = _FakeServer(
      workspaces: [_owner('org-auto', 0), _tenant('ten-1')],
      tenancies: {'active': 1},
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(h.location, '/tenant/dashboard');
    expect(server.ensureOrgCalls, 0);

    // Empty owner workspaces are not offered as a switch target either.
    expect(
      switchableWorkspaces(server.workspaces, currentKey: 'tenancy:ten-1'),
      isEmpty,
    );
  });

  testWidgets('a selection the server rejects opens nothing', (tester) async {
    final server = _FakeServer(
      workspaces: [_tenant('ten-1')],
      tenancies: {'active': 1},
    )..rejectSelection = true;
    final h = _Harness(server);
    await h.pump(tester);
    Object? error;
    await h.run(tester, () async {
      try {
        await completeLogin(h.context, h.ref);
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<DioException>());
    expect(server.selected, isNull);
    expect(h.location, '/start');
  });

  testWidgets('after logout the session is gone; logging in again routes the same',
      (tester) async {
    final server = _FakeServer(
      workspaces: [_owner('org-auto', 0), _tenant('ten-1')],
      tenancies: {'active': 1},
    );
    final h = _Harness(server);
    await h.pump(tester);
    await h.login(tester);
    expect(h.location, '/tenant/dashboard');

    await AuthStorage.clearAll();
    expect(await AuthStorage.hasPersistedSession(), isFalse);

    server.calls.clear();
    Object? error;
    await h.run(tester, () async {
      try {
        await restoreSession(h.context, h.ref);
      } catch (e) {
        error = e;
      }
    });
    expect(error, isNotNull);
    expect(server.calls, isEmpty);

    // Next OTP login (tokens stored again) lands on the tenant dashboard.
    await AuthStorage.writeAccessToken('token-2');
    await h.login(tester);
    expect(h.location, '/tenant/dashboard');
    expect(server.ensureOrgCalls, 0);
  });

  group('resolveLoginDestination', () {
    const none = TenancySummary();

    test('tenant beats an empty owner workspace', () {
      final d = resolveLoginDestination(
        workspaces: [_owner('o', 0), _tenant('t')],
        tenancies: const TenancySummary(active: 1),
      );
      expect((d as OpenWorkspace).workspace['id'], 't');
    });

    test('an owner with properties is the default; last-used wins when listed', () {
      final both = [_tenant('t'), _owner('o', 3)];
      expect(
        (resolveLoginDestination(workspaces: both, tenancies: none) as OpenWorkspace)
            .workspace['id'],
        'o',
      );
      expect(
        (resolveLoginDestination(
          workspaces: both,
          tenancies: none,
          lastWorkspace: 'tenancy:t',
        ) as OpenWorkspace)
            .workspace['id'],
        't',
      );
      expect(
        (resolveLoginDestination(
          workspaces: both,
          tenancies: none,
          lastWorkspace: 'tenancy:gone',
        ) as OpenWorkspace)
            .workspace['id'],
        'o',
      );
    });

    test('older servers without per-workspace counts use /me propertyCount', () {
      final legacy = {..._owner('o', 0)}..remove('propertyCount');
      expect(
        resolveLoginDestination(
          workspaces: [legacy],
          tenancies: none,
          fallbackPropertyCount: 2,
        ),
        isA<OpenWorkspace>(),
      );
    });

    test('pending wins over ended, and neither becomes owner setup', () {
      final d = resolveLoginDestination(
        workspaces: [_owner('o', 0)],
        tenancies: const TenancySummary(pending: 1, ended: 2),
      );
      expect((d as TenancyUnavailable).status, 'pending');
    });

    test('no memberships at all is a new owner', () {
      final d = resolveLoginDestination(workspaces: [], tenancies: none);
      expect((d as OwnerSetup).workspace, isNull);
    });
  });
}
