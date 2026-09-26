// features/structure/presentation/hostel_pg_dashboard_body.dart
//
// Hostel/PG dashboard — layout locked to Dormly_HostelPG_Dashboard_Reference_Pack
// (01_exact_dashboard_reference.png). Data from existing providers only.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/user_profile.dart';
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../../properties/presentation/property_switcher_sheet.dart';
import '../domain/hierarchy_level.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider, nodeCountProvider;

/// Colors sampled from 01_exact_dashboard_reference.png
class HostelPgDashboardColors {
  static const bg = Color(0xFF0D1623);
  static const card = Color(0xFF151F30);
  static const cardElevated = Color(0xFF172337);
  static const cardBorder = Color(0x14FFFFFF);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF94A3B8);
  static const purple = Color(0xFF8B5CF6);
  static const purpleBright = Color(0xFF7C3AED);
  static const blue = Color(0xFF3B82F6);
  static const cyan = Color(0xFF22D3EE);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFF87171);
  static const orange = Color(0xFFF2835F);
}

class HostelPgDashboardBody extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final bool canManage;
  final String greeting;
  final String firstName;
  final UserProfile? profile;
  final int notificationCount;
  final String Function(String?) avatarUrlResolver;
  final String propertySubtitle;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final Future<void> Function() onRefresh;
  final VoidCallback? onAddTenant;
  final VoidCallback? onNewInvoice;
  final VoidCallback? onAddExpense;
  final VoidCallback? onCollectedTap;
  final VoidCallback? onExpensesTap;
  final VoidCallback? onNetProfitTap;
  final VoidCallback? onViewAllRooms;
  /// Occupancy unit noun, e.g. Bed / Flat / Space.
  final String unitKind;
  /// Container noun for totals, e.g. Room / Flat / Space.
  final String containerKind;

  const HostelPgDashboardBody({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.canManage,
    required this.greeting,
    required this.firstName,
    required this.profile,
    required this.notificationCount,
    required this.avatarUrlResolver,
    required this.propertySubtitle,
    required this.onNotifications,
    required this.onProfile,
    required this.onRefresh,
    this.onAddTenant,
    this.onNewInvoice,
    this.onAddExpense,
    this.onCollectedTap,
    this.onExpensesTap,
    this.onNetProfitTap,
    this.onViewAllRooms,
    this.unitKind = 'Bed',
    this.containerKind = 'Room',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(propertyDashboardProvider(propertyId));
    final levelsAsync = ref.watch(hierarchyLevelsProvider(propertyId));
    final roomLevelId = _roomLevelId(levelsAsync.valueOrNull);
    final roomCountAsync = roomLevelId == null
        ? const AsyncValue<int>.data(0)
        : ref.watch(nodeCountProvider((propertyId, roomLevelId)));

    // Minimal clearance so Room Occupancy can sit above fixed nav without huge empty space.
    final bottomClearance = 48.0 + MediaQuery.paddingOf(context).bottom;

    return Material(
      color: HostelPgDashboardColors.bg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: HostelPgDashboardColors.purple,
          backgroundColor: HostelPgDashboardColors.card,
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, 6, 16, bottomClearance),
            children: [
              _Header(
                greeting: greeting,
                name: firstName,
                notificationCount: notificationCount,
                onNotifications: onNotifications,
                onProfile: onProfile,
              ),
              const SizedBox(height: 10),
              dashboardAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: HostelPgDashboardColors.purple,
                    ),
                  ),
                ),
                error: (_, __) => _ErrorCard(
                  onRetry: () =>
                      ref.invalidate(propertyDashboardProvider(propertyId)),
                ),
                data: (dashboard) {
                  final hero = dashboard.heroStats;
                  final overview = dashboard.overview;
                  final occupiedBeds = hero.occupiedUnits;
                  final vacantBeds = hero.availableUnits;
                  final totalBeds = hero.totalUnits;
                  final occupancyPct = totalBeds <= 0
                      ? 0
                      : ((occupiedBeds / totalBeds) * 100)
                          .round()
                          .clamp(0, 100);
                  final totalRooms = roomCountAsync.valueOrNull ?? 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroCard(
                        propertyId: propertyId,
                        propertyName: propertyName,
                        subtitle: propertySubtitle,
                        occupancyPct: occupancyPct,
                        isOccupied: occupiedBeds > 0,
                        occupiedBeds: occupiedBeds,
                        vacantBeds: vacantBeds,
                        totalRooms: totalRooms,
                        unitKind: unitKind,
                        containerKind: containerKind,
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 10),
                        _QuickActions(
                          onAddTenant: onAddTenant,
                          onNewInvoice: onNewInvoice,
                          onAddExpense: onAddExpense,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _SectionTitle(
                        title: 'Financial Overview',
                        trailing: _MonthPill(),
                      ),
                      const SizedBox(height: 8),
                      _FinancePair(
                        collected: overview.rentReceived,
                        expenses: overview.totalExpenses,
                        onCollectedTap: onCollectedTap,
                        onExpensesTap: onExpensesTap,
                      ),
                      const SizedBox(height: 8),
                      _NetProfitCard(
                        netProfit: overview.netProfit,
                        onTap: onNetProfitTap,
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle(
                        title: '$containerKind Occupancy',
                        trailing: GestureDetector(
                          onTap: onViewAllRooms,
                          child: const Text(
                            'View All →',
                            style: TextStyle(
                              color: HostelPgDashboardColors.purple,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _OccupancyCard(
                        occupancyPct: occupancyPct,
                        occupiedBeds: occupiedBeds,
                        vacantBeds: vacantBeds,
                        totalRooms: totalRooms,
                        onTap: onViewAllRooms,
                        unitKind: unitKind,
                        containerKind: containerKind,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _roomLevelId(List<HierarchyLevel>? levels) {
    if (levels == null || levels.isEmpty) return null;
    final room = levels.where((l) {
      final key = l.internalKey.toLowerCase();
      return key == 'room' || key.startsWith('room_');
    }).firstOrNull;
    return room?.id;
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final String name;
  final int notificationCount;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  const _Header({
    required this.greeting,
    required this.name,
    required this.notificationCount,
    required this.onNotifications,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$greeting, $name ',
                      style: const TextStyle(
                        color: HostelPgDashboardColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const TextSpan(
                      text: '👋',
                      style: TextStyle(fontSize: 18, height: 1.15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Manage your hostel/PG efficiently today.',
                style: TextStyle(
                  color: HostelPgDashboardColors.textSecondary,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onNotifications,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: HostelPgDashboardColors.textPrimary,
                size: 22,
              ),
            ),
            if (notificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 2),
        GestureDetector(
          onTap: onProfile,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: HostelPgDashboardColors.purpleBright,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ONE unified hero card — building blends on the right; beds/rooms in bottom strip.
class _HeroCard extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final String subtitle;
  final int occupancyPct;
  final bool isOccupied;
  final int occupiedBeds;
  final int vacantBeds;
  final int totalRooms;
  final String unitKind;
  final String containerKind;

  const _HeroCard({
    required this.propertyId,
    required this.propertyName,
    required this.subtitle,
    required this.occupancyPct,
    required this.isOccupied,
    required this.occupiedBeds,
    required this.vacantBeds,
    required this.totalRooms,
    required this.unitKind,
    required this.containerKind,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bar = (occupancyPct / 100).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101B2C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: HostelPgDashboardColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Upper: occupancy + building (seamless blend)
          SizedBox(
            height: 158,
            child: LayoutBuilder(
              builder: (context, upper) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF101B2C)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.58,
                        heightFactor: 1,
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0x00000000),
                                Color(0x66000000),
                                Color(0xFF000000),
                                Color(0xFF000000),
                              ],
                              stops: [0.0, 0.18, 0.42, 1.0],
                            ).createShader(bounds);
                          },
                          child: Image.asset(
                            'assets/images/building picture.png',
                            fit: BoxFit.cover,
                            alignment: const Alignment(0.15, 0),
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Color(0xFF1A2233)),
                          ),
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFF101B2C),
                            Color(0xE6101B2C),
                            Color(0x66101B2C),
                            Color(0x00101B2C),
                          ],
                          stops: [0.0, 0.28, 0.55, 0.78],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B1A33),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                      color: const Color(0x554B76F1)),
                                ),
                                child: const Icon(
                                  Icons.apartment_rounded,
                                  color: Color(0xFF93C5FD),
                                  size: 17,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      propertyName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xB3CBD5E1),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Material(
                                color: const Color(0x66243044),
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => showPropertySwitcherSheet(
                                    context,
                                    ref,
                                    currentPropertyId: propertyId,
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'All Properties',
                                          style: TextStyle(
                                            color: Color(0xEBFFFFFF),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 14,
                                          color: Color(0xE6FFFFFF),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isOccupied
                                      ? HostelPgDashboardColors.green
                                      : HostelPgDashboardColors.textSecondary,
                                  shape: BoxShape.circle,
                                  boxShadow: isOccupied
                                      ? const [
                                          BoxShadow(
                                            color: Color(0xAA22C55E),
                                            blurRadius: 6,
                                            spreadRadius: 0.5,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOccupied ? 'Occupied' : 'Vacant',
                                style: TextStyle(
                                  color: isOccupied
                                      ? HostelPgDashboardColors.green
                                      : HostelPgDashboardColors.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$occupancyPct%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1,
                                  ),
                                ),
                                const TextSpan(
                                  text: '  Occupied',
                                  style: TextStyle(
                                    color: Color(0xE6FFFFFF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: upper.maxWidth * 0.48,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: SizedBox(
                                height: 8,
                                child: Stack(
                                  children: [
                                    const Positioned.fill(
                                      child: ColoredBox(
                                          color: Color(0x55334155)),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: bar,
                                      child: const DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF8B5CF6),
                                              Color(0xFF4B76F1),
                                              Color(0xFF22D3EE),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Bottom stats — same card, compact
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0C1522),
              border: Border(
                top: BorderSide(color: Color(0x18FFFFFF)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              children: [
                _InlineStat(
                  icon: Icons.bed_outlined,
                  value: '$occupiedBeds',
                  label: 'Occupied ${unitKind}s',
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: const Color(0x22FFFFFF),
                ),
                _InlineStat(
                  icon: Icons.bed_outlined,
                  value: '$vacantBeds',
                  label: 'Vacant ${unitKind}s',
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: const Color(0x22FFFFFF),
                ),
                _InlineStat(
                  icon: Icons.apartment_outlined,
                  value: '$totalRooms',
                  label: 'Total ${containerKind}s',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _InlineStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: HostelPgDashboardColors.textPrimary),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(
                  color: HostelPgDashboardColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HostelPgDashboardColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// IMAGE 1: tinted cards + large circular purple / orange / green icons.
class _QuickActions extends StatelessWidget {
  final VoidCallback? onAddTenant;
  final VoidCallback? onNewInvoice;
  final VoidCallback? onAddExpense;

  const _QuickActions({
    this.onAddTenant,
    this.onNewInvoice,
    this.onAddExpense,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            label: 'Add Tenant',
            icon: Icons.person_add_alt_1_rounded,
            cardColor: const Color(0xFF3B2B78),
            iconColor: const Color(0xFF8B5CF6),
            onTap: onAddTenant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            label: 'New Invoice',
            icon: Icons.receipt_long_rounded,
            cardColor: const Color(0xFF4A3228),
            iconColor: const Color(0xFFF2835F),
            onTap: onNewInvoice,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            label: 'Add Expense',
            icon: Icons.credit_card_rounded,
            cardColor: const Color(0xFF14463F),
            iconColor: const Color(0xFF06AD6A),
            onTap: onAddExpense,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color cardColor;
  final Color iconColor;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.label,
    required this.icon,
    required this.cardColor,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 82,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: HostelPgDashboardColors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _MonthPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x338B5CF6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This Month',
            style: TextStyle(
              color: HostelPgDashboardColors.purple,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: HostelPgDashboardColors.purple,
          ),
        ],
      ),
    );
  }
}

class _FinancePair extends StatelessWidget {
  final double collected;
  final double expenses;
  final VoidCallback? onCollectedTap;
  final VoidCallback? onExpensesTap;

  const _FinancePair({
    required this.collected,
    required this.expenses,
    this.onCollectedTap,
    this.onExpensesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FinanceCard(
            bg: const Color(0xFF1B2350),
            icon: Icons.bar_chart_rounded,
            iconColor: HostelPgDashboardColors.purple,
            value: _inr(collected),
            label: 'Collected',
            badge: collected > 0 ? '↑ 12%' : null,
            badgeColor: HostelPgDashboardColors.green,
            onTap: onCollectedTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FinanceCard(
            bg: const Color(0xFF3E232B),
            icon: Icons.description_outlined,
            iconColor: HostelPgDashboardColors.red,
            value: _inr(expenses),
            label: 'Expenses',
            badge: expenses > 0 ? '↑ 8%' : null,
            badgeColor: HostelPgDashboardColors.red,
            onTap: onExpensesTap,
          ),
        ),
      ],
    );
  }
}

class _FinanceCard extends StatelessWidget {
  final Color bg;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;

  const _FinanceCard({
    required this.bg,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.badge,
    this.badgeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 18),
                  const Spacer(),
                  if (badge != null && badgeColor != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor!.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: HostelPgDashboardColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: const TextStyle(
                  color: HostelPgDashboardColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetProfitCard extends StatelessWidget {
  final double netProfit;
  final VoidCallback? onTap;

  const _NetProfitCard({required this.netProfit, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF172046),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0x338B5CF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: HostelPgDashboardColors.purple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _inr(netProfit),
                      style: const TextStyle(
                        color: HostelPgDashboardColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Net Profit',
                      style: TextStyle(
                        color: HostelPgDashboardColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 88,
                height: 36,
                child: CustomPaint(
                  painter: _SparklinePainter(color: HostelPgDashboardColors.cyan),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.18, size.height * 0.5),
      Offset(size.width * 0.34, size.height * 0.58),
      Offset(size.width * 0.52, size.height * 0.3),
      Offset(size.width * 0.7, size.height * 0.38),
      Offset(size.width * 0.86, size.height * 0.12),
      Offset(size.width, size.height * 0.2),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final m = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, a.dy, m.dx, m.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.drawCircle(pts.last, 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.color != color;
}

class _OccupancyCard extends StatelessWidget {
  final int occupancyPct;
  final int occupiedBeds;
  final int vacantBeds;
  final int totalRooms;
  final VoidCallback? onTap;
  final String unitKind;
  final String containerKind;

  const _OccupancyCard({
    required this.occupancyPct,
    required this.occupiedBeds,
    required this.vacantBeds,
    required this.totalRooms,
    this.onTap,
    required this.unitKind,
    required this.containerKind,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HostelPgDashboardColors.cardElevated,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CustomPaint(
                  painter: _DonutPainter(
                    progress: (occupancyPct / 100).clamp(0.0, 1.0),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$occupancyPct%',
                          style: const TextStyle(
                            color: HostelPgDashboardColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Occupied',
                          style: TextStyle(
                            color: HostelPgDashboardColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    _Legend(
                      color: HostelPgDashboardColors.green,
                      label: 'Occupied',
                      value: '$occupiedBeds',
                    ),
                    const SizedBox(height: 10),
                    _Legend(
                      color: HostelPgDashboardColors.purple,
                      label: 'Vacant',
                      value: '$vacantBeds',
                    ),
                    const SizedBox(height: 10),
                    _Legend(
                      color: HostelPgDashboardColors.blue,
                      label: 'Total ${containerKind}s',
                      value: '$totalRooms',
                      icon: Icons.apartment_outlined,
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
}

class _DonutPainter extends CustomPainter {
  final double progress;
  _DonutPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const stroke = 12.0;
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFF2A3142)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    if (progress <= 0) return;
    final sweep = math.pi * 2 * progress;
    void seg(double start, double part, Color color) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + sweep * start,
        sweep * part,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    seg(0, 0.55, HostelPgDashboardColors.purple);
    seg(0.55, 0.28, HostelPgDashboardColors.cyan);
    seg(0.83, 0.17, HostelPgDashboardColors.green);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.progress != progress;
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final IconData? icon;

  const _Legend({
    required this.color,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null)
          Icon(icon, size: 13, color: color)
        else
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: HostelPgDashboardColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: HostelPgDashboardColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HostelPgDashboardColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Could not load dashboard data.',
            style: TextStyle(color: HostelPgDashboardColors.textPrimary),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

String _inr(num value) {
  if (value <= 0) return '₹0';
  return '₹${value.toStringAsFixed(0)}';
}
