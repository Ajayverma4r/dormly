import 'package:dio/dio.dart';
import 'package:dormly/features/expenses/data/expense_repository.dart';
import 'package:dormly/features/expenses/domain/expense.dart';
import 'package:dormly/features/expenses/presentation/expense_history_screen.dart';
import 'package:dormly/features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show contextRoleProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _p1 = '11000000-0000-4000-8000-000000000001';

final _expense = Expense(
  id: 'e1',
  title: 'Plumber visit',
  amount: 1200,
  date: DateTime.now(),
  category: 'maintenance',
);

class _FakeRepo implements ExpenseRepository {
  final deleted = <(String, String)>[];
  Object? failWith;

  @override
  Future<void> delete(String propertyId, String expenseId) async {
    if (failWith != null) throw failWith!;
    deleted.add((propertyId, expenseId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _dio(int status) => DioException(
      requestOptions: RequestOptions(path: '/v1/properties/$_p1/expenses/e1'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: {'error': 'Requires one of roles: owner, admin'},
      ),
      type: DioExceptionType.badResponse,
    );

Future<void> _openExpense(WidgetTester tester, String? role, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contextRoleProvider.overrideWith((ref) async => role),
        expensesProvider.overrideWith((ref, id) async => [_expense]),
        expenseRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: ExpenseHistoryScreen(propertyId: _p1)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plumber visit'));
  await tester.pumpAndSettle();
}

Future<void> _deleteAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('expense-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Delete'));
  await tester.pumpAndSettle();
}

void main() {
  for (final role in ['owner', 'admin']) {
    testWidgets('$role sees Delete Expense and can delete', (tester) async {
      final repo = _FakeRepo();
      await _openExpense(tester, role, repo);
      expect(find.byKey(const Key('expense-delete')), findsOneWidget);

      await _deleteAndConfirm(tester);
      expect(repo.deleted, [(_p1, 'e1')]);
    });
  }

  for (final role in ['manager', 'staff', 'tenant', null]) {
    testWidgets('${role ?? 'unknown role'} has no way to delete an expense',
        (tester) async {
      final repo = _FakeRepo();
      await _openExpense(tester, role, repo);
      expect(find.text('Plumber visit'), findsWidgets, reason: 'detail is still viewable');
      expect(find.byKey(const Key('expense-delete')), findsNothing);
      expect(find.text('Delete Expense'), findsNothing);
      expect(repo.deleted, isEmpty);
    });
  }

  testWidgets('a refused delete shows a friendly message, never Dio details',
      (tester) async {
    // e.g. the workspace role changed to manager after the sheet opened.
    final repo = _FakeRepo()..failWith = _dio(403);
    await _openExpense(tester, 'owner', repo);
    await _deleteAndConfirm(tester);

    expect(find.text('Only the property owner or an admin can delete expenses.'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('Requires one of roles'), findsNothing);
    expect(find.byKey(const Key('expense-delete')), findsOneWidget, reason: 'sheet stays open');
  });

  test('error messages never include server or exception text', () {
    expect(expenseDeleteErrorMessage(_dio(404)), 'This expense no longer exists.');
    for (final error in [_dio(500), Exception('socket closed'), StateError('x')]) {
      final message = expenseDeleteErrorMessage(error);
      expect(message, 'Could not delete the expense. Please try again.');
    }
  });

  test('only owner and admin may delete expenses', () {
    expect(canDeleteExpenses('owner'), isTrue);
    expect(canDeleteExpenses('admin'), isTrue);
    for (final role in ['manager', 'staff', 'tenant', null, '']) {
      expect(canDeleteExpenses(role), isFalse);
    }
  });
}
