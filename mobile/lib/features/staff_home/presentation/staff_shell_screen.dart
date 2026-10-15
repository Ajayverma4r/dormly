// features/staff_home/presentation/staff_shell_screen.dart
//
// Staff bottom nav (5 tabs): Home · Complaints · Rooms · Gate Passes · More.
// Owner/admin/manager use PropertyShellScreen; this shell never offers
// billing, tenancy editing or structure changes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import 'staff_gate_passes_screen.dart';
import 'staff_home_tab.dart';
import 'staff_more_screen.dart';
import 'staff_rooms_screen.dart';
import 'staff_ui.dart';

class StaffShellScreen extends StatefulWidget {
  final String propertyId;
  final String propertyName;

  const StaffShellScreen(
      {super.key, required this.propertyId, required this.propertyName});

  @override
  State<StaffShellScreen> createState() => _StaffShellScreenState();
}

class _StaffShellScreenState extends State<StaffShellScreen> {
  static const home = 0, complaints = 1, rooms = 2, gatePasses = 3;

  int _index = home;
  bool _exitDialogOpen = false;

  void _goTo(int i) => setState(() => _index = i);

  void _handleBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (_index != home) {
      setState(() => _index = home);
      return;
    }
    _confirmExit(context);
  }

  Future<void> _confirmExit(BuildContext context) async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    try {
      final exit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exit App'),
          content: const Text('Are you sure you want to exit?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: StaffColors.brand),
              child: const Text('Yes, Exit'),
            ),
          ],
        ),
      );
      if (exit == true) await SystemNavigator.pop();
    } finally {
      _exitDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.propertyId;
    final tabs = [
      StaffHomeTab(
        propertyId: id,
        propertyName: widget.propertyName,
        onOpenComplaints: () => _goTo(complaints),
        onOpenRooms: () => _goTo(rooms),
        onOpenGatePasses: () => _goTo(gatePasses),
      ),
      ComplaintsListScreen(propertyId: id, asTab: true),
      StaffRoomsScreen(propertyId: id, asTab: true),
      StaffGatePassesScreen(propertyId: id, asTab: true),
      StaffMoreScreen(propertyId: id, propertyName: widget.propertyName),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(context);
      },
      child: Scaffold(
        key: const Key('staff-shell'),
        backgroundColor: StaffColors.bg,
        body: IndexedStack(
            index: _index, sizing: StackFit.expand, children: tabs),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: StaffColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? StaffColors.brand : StaffColors.muted,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                      color: selected ? StaffColors.brand : StaffColors.muted);
                }),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _goTo,
                height: 64,
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                indicatorColor: StaffColors.brandSoft,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.report_problem_outlined),
                    selectedIcon: Icon(Icons.report_problem_rounded),
                    label: 'Complaints',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bed_outlined),
                    selectedIcon: Icon(Icons.bed_rounded),
                    label: 'Rooms',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.badge_outlined),
                    selectedIcon: Icon(Icons.badge_rounded),
                    label: 'Gate Passes',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz_rounded),
                    selectedIcon: Icon(Icons.more_horiz_rounded),
                    label: 'More',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
