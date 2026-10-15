import 'package:dormly/features/auth/data/auth_repository.dart';
import 'package:dormly/features/auth/presentation/login_flow.dart' show invalidateWorkspaceRole;
import 'package:dormly/features/auth/presentation/role_gate.dart';
import 'package:dormly/features/complaints/presentation/complaint_ui.dart';
import 'package:dormly/features/complaints/presentation/complaints_list_screen.dart';
import 'package:dormly/features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _p1 = '11000000-0000-4000-8000-000000000001';

/// The stored workspace: what AuthStorage would hold after selectContext.
class _FakeAuthRepo implements AuthRepository {
  String? role;
  String? userId;
  _FakeAuthRepo(this.role, {this.userId});

  @override
  Future<String?> getContextRole() async => role;

  @override
  Future<String?> getUserId() async => userId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget home, _FakeAuthRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        complaintsProvider.overrideWith((ref, id) async => const []),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

const _structure = RoleGate(
  allowed: propertyManagerRoles,
  child: Scaffold(body: Text('Structure editor')),
);

void main() {
  group('structure editor deep link', () {
    for (final role in ['owner', 'admin', 'manager']) {
      testWidgets('$role can open it', (tester) async {
        await _pump(tester, _structure, _FakeAuthRepo(role));
        expect(find.text('Structure editor'), findsOneWidget);
        expect(find.byType(RestrictedAccessScreen), findsNothing);
      });
    }

    for (final role in ['staff', 'tenant', null, 'superadmin']) {
      testWidgets('${role ?? 'no role'} is shown the restricted screen', (tester) async {
        await _pump(tester, _structure, _FakeAuthRepo(role));
        expect(find.text('Structure editor'), findsNothing);
        expect(find.byType(RestrictedAccessScreen), findsOneWidget);
      });
    }
  });

  group('property dashboard deep link', () {
    Widget dashboard() => const DynamicDashboardScreen(propertyId: _p1, propertyName: 'Sky');

    testWidgets('staff land on their complaints, not the management shell', (tester) async {
      await _pump(tester, dashboard(), _FakeAuthRepo('staff'));
      expect(find.byType(ComplaintsListScreen), findsOneWidget);
      expect(find.byType(RestrictedAccessScreen), findsNothing);
    });

    testWidgets('a tenant workspace never renders the management shell', (tester) async {
      await _pump(tester, dashboard(), _FakeAuthRepo('tenant'));
      expect(find.byType(RestrictedAccessScreen), findsOneWidget);
      expect(find.text('Go to my stay'), findsOneWidget);
      expect(find.byType(ComplaintsListScreen), findsNothing);
    });

    testWidgets('an unknown or missing role is restricted', (tester) async {
      for (final role in [null, 'viewer']) {
        await _pump(tester, dashboard(), _FakeAuthRepo(role));
        expect(find.byType(RestrictedAccessScreen), findsOneWidget);
        expect(find.text('Back to properties'), findsOneWidget);
      }
    });
  });

  group('workspace switching', () {
    testWidgets('screens re-read the role and user after a switch', (tester) async {
      final repo = _FakeAuthRepo('manager', userId: 'manager-user');
      String? viewerRole;
      String? viewerId;
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            viewerRole = ref.watch(complaintViewerRoleProvider).valueOrNull;
            viewerId = ref.watch(complaintViewerUserIdProvider).valueOrNull;
            return Column(
              children: [
                const Expanded(child: _structure),
                TextButton(
                  onPressed: () => invalidateWorkspaceRole(ref),
                  child: const Text('switched'),
                ),
              ],
            );
          },
        ),
        repo,
      );
      expect(find.text('Structure editor'), findsOneWidget);
      expect((viewerRole, viewerId), ('manager', 'manager-user'));

      // The stored workspace changes, as selectContext does.
      repo
        ..role = 'staff'
        ..userId = 'staff-user';
      await tester.pumpAndSettle();
      expect(find.text('Structure editor'), findsOneWidget, reason: 'still cached');

      await tester.tap(find.text('switched'));
      await tester.pumpAndSettle();
      expect(find.text('Structure editor'), findsNothing);
      expect(find.byType(RestrictedAccessScreen), findsOneWidget);
      expect((viewerRole, viewerId), ('staff', 'staff-user'));
    });
  });

  group('complaint action permissions', () {
    const me = 'u-staff';
    test('staff act only on complaints assigned to them once assignment exists', () {
      expect(canActOnComplaint('staff', me, {'assigned_to': me}), isTrue);
      expect(canActOnComplaint('staff', me, {'assigned_to': 'someone-else'}), isFalse);
      expect(canActOnComplaint('staff', me, {'assigned_to': null}), isFalse);
      expect(canActOnComplaint('staff', null, {'assigned_to': me}), isFalse);
      // Before migration 027 the server sends no assignment and keeps staff updates.
      expect(canActOnComplaint('staff', me, {'id': 'c'}), isTrue);
    });

    test('managers act on every complaint; tenants and unknown roles on none', () {
      expect(canActOnComplaint('manager', 'm', {'assigned_to': 'someone-else'}), isTrue);
      expect(canActOnComplaint('owner', 'o', {'assigned_to': null}), isTrue);
      expect(canActOnComplaint('tenant', 't', {'assigned_to': 't'}), isFalse);
      expect(canActOnComplaint(null, 'x', {}), isFalse);
    });
  });
}
