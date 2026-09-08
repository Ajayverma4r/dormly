// features/structure/presentation/property_dashboard_tab_screen.dart
//
// Premium SaaS-style property dashboard — greeting, hero card, overview grid,
// quick actions. Matches the HomeOwner reference layout (Dormly branding).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/presentation/create_invoice_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../auth/domain/user_profile.dart';
import '../../dashboard/domain/property_dashboard.dart';
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../../expenses/presentation/add_expense_sheet.dart';
import '../../home/presentation/profile_screen.dart' show myProfileProvider;
import '../../notifications/data/notifications_repository.dart';
import '../../properties/presentation/property_switcher_sheet.dart';
import '../../subscription/presentation/widgets/ad_banner_gate.dart';
import '../../subscription/presentation/widgets/expiry_warning_banner.dart';
import '../../tenancies/presentation/add_tenant_screen.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart' show activityProvider;
import 'property_shell_screen.dart' show propertyDetailProvider;

class PropertyDashboardTabScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final bool canManage;
  final VoidCallback? onGoToTenantsTab;
  final VoidCallback? onGoToPaymentsTab;
  final VoidCallback? onGoToRoomsTab;
  final VoidCallback? onGoToMenuTab;

  const PropertyDashboardTabScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
    this.canManage = false,
    this.onGoToTenantsTab,
    this.onGoToPaymentsTab,
    this.onGoToRoomsTab,
    this.onGoToMenuTab,
  });

  static const _canvas = Color(0xFFF8F9FB);
  static const _heroStart = AppColors.primaryDark;
  static const _heroEnd = AppColors.primary;
  static const _brandPurple = AppColors.primary;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstName(UserProfile? profile) {
    final name = profile?.name?.trim();
    if (name == null || name.isEmpty) return 'there';
    return name.split(' ').first;
  }

  String _resolveAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dormly-backend.onrender.com',
    );
    return '$base$path';
  }

  String _propertySubtitle(Map<String, dynamic>? property) {
    if (property == null) return 'Property';
    final type = property['property_type_key']?.toString().replaceAll('_', ' ');
    final city = property['city']?.toString();
    final address = property['address']?.toString();
    final parts = <String>[];
    if (type != null && type.isNotEmpty) {
      parts.add(type[0].toUpperCase() + type.substring(1));
    }
    if (city != null && city.isNotEmpty) {
      parts.add(city);
    } else if (address != null && address.isNotEmpty) {
      parts.add(address);
    }
    return parts.isEmpty ? 'Your property' : parts.join(' · ');
  }

  String _formatCurrency(num value) {
    if (value <= 0) return '₹0';
    return '₹${value.toStringAsFixed(0)}';
  }

  String _availableUnitsLabel(int vacant) {
    if (vacant == 0) return 'Fully occupied';
    if (vacant == 1) return '1 Room Empty';
    return '$vacant Rooms Empty';
  }

  String _occupancyPrimary(HeroStats hero) {
    if (hero.totalUnits <= 0) return '0% Occupied';
    final pct =
        ((hero.occupiedUnits / hero.totalUnits) * 100).round().clamp(0, 100);
    return '$pct% Occupied';
  }

  String _pendingDuesSublabel(int tenantsWithDues) {
    if (tenantsWithDues <= 0) return 'All clear';
    if (tenantsWithDues == 1) return 'from 1 tenant';
    return 'from $tenantsWithDues tenants';
  }

  Future<void> _openNewInvoice(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(propertyId: propertyId),
      ),
    );
    if (created == true) {
      ref.invalidate(propertyDashboardProvider(propertyId));
    }
  }

  Future<void> _openAddTenant(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTenantScreen(propertyId: propertyId),
      ),
    );
    ref.invalidate(propertyDashboardProvider(propertyId));
  }

  List<_InsightAlert> _buildAttentionAlerts(PropertyDashboard dashboard) {
    final alerts = <_InsightAlert>[];
    final kycCount = dashboard.actionableInsights.pendingKycCount;
    final openComplaints = dashboard.overview.openComplaints;

    if (kycCount > 0) {
      alerts.add(_InsightAlert(
        message:
            '$kycCount Tenant${kycCount == 1 ? '' : 's'} pending KYC documents',
        type: _InsightAlertType.kyc,
      ));
    }
    if (openComplaints > 0) {
      alerts.add(_InsightAlert(
        message: openComplaints == 1
            ? '1 Urgent maintenance request pending'
            : '$openComplaints Open maintenance requests pending',
        isUrgent: true,
        type: _InsightAlertType.maintenance,
      ));
    }
    return alerts;
  }

  void _showComingSoon(BuildContext context, String featureName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coming Soon: $featureName')),
    );
  }

  Future<void> _openAddExpense(BuildContext context, WidgetRef ref) async {
    final saved = await showAddExpenseSheet(
      context: context,
      ref: ref,
      propertyId: propertyId,
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense saved'),
          backgroundColor: AppColors.positive,
        ),
      );
    }
  }

  void _onNotifications(BuildContext context) {
    context.push('/notifications');
  }

  void _onProfileTap(BuildContext context) {
    if (onGoToMenuTab != null) {
      onGoToMenuTab!();
    } else {
      context.push('/profile');
    }
  }

  void _openComplaints(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComplaintsListScreen(propertyId: propertyId),
      ),
    );
  }

  Future<void> _refreshDashboard(WidgetRef ref) async {
    ref.invalidate(propertyDashboardProvider(propertyId));
    ref.invalidate(activityProvider(propertyId));
    ref.invalidate(propertyDetailProvider(propertyId));
    ref.invalidate(myProfileProvider);
    ref.invalidate(_notificationCountProvider);

    await Future.wait<Object>([
      ref.read(propertyDashboardProvider(propertyId).future).catchError((_) =>
          const PropertyDashboard(
            heroStats: HeroStats(
              totalUnits: 0,
              occupiedUnits: 0,
              availableUnits: 0,
              expectedMonthlyRent: 0,
            ),
            overview: DashboardOverview(
              totalActiveTenants: 0,
              openComplaints: 0,
              totalExpenses: 0,
              rentReceived: 0,
              rentPending: 0,
            ),
            actionableInsights: ActionableInsights(
              defaulters: [],
              pendingKycCount: 0,
              upcomingVacancies: 0,
            ),
          )),
      ref.read(activityProvider(propertyId).future).catchError((_) => <Map<String, dynamic>>[]),
      ref.read(propertyDetailProvider(propertyId).future).catchError((_) => <String, dynamic>{}),
      ref.read(myProfileProvider.future).catchError((_) => const UserProfile(
            id: '',
            phone: '',
            profileComplete: false,
            propertyCount: 0,
          )),
      ref.read(_notificationCountProvider.future).catchError((_) => 0),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(propertyDashboardProvider(propertyId));
    final activityAsync = ref.watch(activityProvider(propertyId));
    final propertyAsync = ref.watch(propertyDetailProvider(propertyId));
    final profileAsync = ref.watch(myProfileProvider);
    final notificationsAsync = ref.watch(_notificationCountProvider);

    final property = propertyAsync.valueOrNull;
    final propertyTypeKey = property?['property_type_key'] as String?;
    final displayName = property?['name']?.toString() ?? propertyName;

    final notificationCount = notificationsAsync.valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: _brandPurple,
          onRefresh: () => _refreshDashboard(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
            profileAsync.when(
              loading: () => _DashboardHeader(
                greeting: _greeting(),
                name: '…',
                notificationCount: notificationCount,
                profile: null,
                avatarUrlResolver: _resolveAvatarUrl,
                onNotifications: () => _onNotifications(context),
                onProfile: () => _onProfileTap(context),
              ),
              error: (_, __) => _DashboardHeader(
                greeting: _greeting(),
                name: 'there',
                notificationCount: notificationCount,
                profile: null,
                avatarUrlResolver: _resolveAvatarUrl,
                onNotifications: () => _onNotifications(context),
                onProfile: () => _onProfileTap(context),
              ),
              data: (p) => _DashboardHeader(
                greeting: _greeting(),
                name: _firstName(p),
                notificationCount: notificationCount,
                profile: p,
                avatarUrlResolver: _resolveAvatarUrl,
                onNotifications: () => _onNotifications(context),
                onProfile: () => _onProfileTap(context),
              ),
            ),
            const SizedBox(height: 16),
            const ExpiryWarningBanner(),
            dashboardAsync.when(
              loading: () => const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroSkeleton(),
                  SizedBox(height: 28),
                  _OverviewSkeleton(),
                  SizedBox(height: 28),
                  _InsightsSkeleton(),
                ],
              ),
              error: (err, _) => _DashboardError(
                message: 'Could not load dashboard data.',
                onRetry: () =>
                    ref.invalidate(propertyDashboardProvider(propertyId)),
              ),
              data: (dashboard) {
                final hero = dashboard.heroStats;
                final overview = dashboard.overview;
                final insights = dashboard.actionableInsights;
                final attentionAlerts = _buildAttentionAlerts(dashboard);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroCard(
                      propertyName: displayName,
                      subtitle: _propertySubtitle(property),
                      isOccupied: hero.occupiedUnits > 0,
                      occupancyPrimary: _occupancyPrimary(hero),
                      occupancySubtitle:
                          _availableUnitsLabel(hero.availableUnits),
                      rentalValueLabel: 'Total Rental Value',
                      rentalValue: _formatCurrency(hero.expectedMonthlyRent),
                      propertyId: propertyId,
                      onOccupancyTap: onGoToRoomsTab,
                      onRentalValueTap: onGoToPaymentsTab,
                    ),
                    if (canManage) ...[
                      const SizedBox(height: 16),
                      _PrimaryQuickActionsRow(
                        onAddTenant: () => _openAddTenant(context, ref),
                        onNewInvoice: () => _openNewInvoice(context, ref),
                        onAddExpense: () => _openAddExpense(context, ref),
                      ),
                    ],
                    const SizedBox(height: 28),
                    const _SectionTitle('Financial Overview'),
                    const SizedBox(height: 12),
                    _NetProfitStrip(
                      collected: overview.rentReceived,
                      expenses: overview.totalExpenses,
                      netProfit: overview.netProfit,
                      formatCurrency: _formatCurrency,
                      onCollectedTap: onGoToPaymentsTab,
                      onExpensesTap: () => _openAddExpense(context, ref),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _OverviewCard(
                          icon: Icons.receipt_long_outlined,
                          iconColor: const Color(0xFF0891B2),
                          iconBg: const Color(0xFFCFFAFE),
                          label: 'Billed This Month',
                          value: _formatCurrency(overview.billedThisMonth),
                          sublabel: 'Invoices generated',
                          onTap: onGoToPaymentsTab,
                        ),
                        _OverviewCard(
                          icon: Icons.timelapse_outlined,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFEF3C7),
                          label: 'Pending Dues',
                          value: _formatCurrency(overview.rentPending),
                          sublabel:
                              _pendingDuesSublabel(overview.tenantsWithDues),
                          onTap: onGoToPaymentsTab,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle('Property Operations'),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _OverviewCard(
                          icon: Icons.people_outline_rounded,
                          iconColor: AppColors.blueprint,
                          iconBg: AppColors.primarySoft,
                          label: 'Total Tenants',
                          value: '${overview.totalActiveTenants}',
                          sublabel: 'Active',
                          onTap: onGoToTenantsTab,
                        ),
                        _OverviewCard(
                          icon: Icons.report_problem_outlined,
                          iconColor: const Color(0xFFEA580C),
                          iconBg: const Color(0xFFFFEDD5),
                          label: 'Open Complaints',
                          value: '${overview.openComplaints}',
                          sublabel: 'Needs Action',
                          onTap: () => _openComplaints(context),
                        ),
                      ],
                    ),
                    if (attentionAlerts.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const _SectionTitle('Needs Attention'),
                      const SizedBox(height: 12),
                      _NeedsAttentionSection(
                        alerts: attentionAlerts,
                        onKycTap: onGoToTenantsTab,
                        onMaintenanceTap: () => _openComplaints(context),
                      ),
                    ],
                    const SizedBox(height: 28),
                    const _SectionTitle('Rent Defaulters'),
                    const SizedBox(height: 12),
                    _RentDefaultersSection(defaulters: insights.defaulters),
                    const SizedBox(height: 28),
                    const _SectionTitle('Upcoming Vacancies'),
                    const SizedBox(height: 12),
                    _UpcomingVacanciesCard(
                      noticeCount: insights.upcomingVacancies,
                    ),
                  ],
                );
              },
            ),
            if (canManage) ...[
              const SizedBox(height: 28),
              const Text(
                'More Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 20,
                alignment: WrapAlignment.start,
                children: [
                  _QuickAction(
                    icon: Icons.home_work_outlined,
                    label: 'Add Property',
                    color: _brandPurple,
                    onTap: () => context.push('/onboarding/create-property'),
                  ),
                  _QuickAction(
                    icon: Icons.support_agent_outlined,
                    label: 'Support',
                    color: const Color(0xFF9333EA),
                    onTap: () => _showComingSoon(context, 'Support'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            const Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            activityAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Could not load activity: $err'),
              data: (items) {
                if (items.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'No activity yet.',
                      style: TextStyle(color: AppColors.slate),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: items.take(5).map((item) {
                      final isPayment = item['type'] == 'payment';
                      return ListTile(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Opening transaction details...'),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          backgroundColor: isPayment
                              ? const Color(0xFFDCFCE7)
                              : AppColors.primarySoft,
                          child: Icon(
                            isPayment
                                ? Icons.payments_outlined
                                : Icons.person_add_alt_outlined,
                            color: isPayment
                                ? AppColors.positive
                                : AppColors.blueprint,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          isPayment
                              ? 'Payment received: ${item['title']}'
                              : 'New resident: ${item['title']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          isPayment
                              ? item['subtitle'].toString()
                              : 'Moved into ${item['subtitle']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate,
                          ),
                        ),
                        trailing: Text(
                          item['ts'].toString().split('T').first,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.slate,
                          ),
                        ),
                      );
                    }).toList(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Center(child: AdBannerGate(propertyTypeKey: propertyTypeKey)),
          ],
        ),
        ),
      ),
    );
  }
}

final _notificationCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final list = await ref.watch(notificationsRepositoryProvider).list();
  return list.length;
});

class _DashboardHeader extends StatelessWidget {
  final String greeting;
  final String name;
  final int notificationCount;
  final UserProfile? profile;
  final String Function(String?) avatarUrlResolver;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  const _DashboardHeader({
    required this.greeting,
    required this.name,
    required this.notificationCount,
    required this.profile,
    required this.avatarUrlResolver,
    required this.onNotifications,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = avatarUrlResolver(profile?.avatarUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '$greeting, $name 👋',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onNotifications,
                  icon: const Icon(Icons.notifications_outlined,
                      color: AppColors.ink),
                ),
                if (notificationCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        notificationCount > 9 ? '9+' : '$notificationCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onProfile,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEDE9FE),
                  backgroundImage:
                      avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl.isEmpty
                      ? const Icon(Icons.person,
                          color: PropertyDashboardTabScreen._brandPurple)
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "Here's what's happening with your properties.",
          style: TextStyle(
            fontSize: 14,
            color: AppColors.slate,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends ConsumerWidget {
  final String propertyName;
  final String subtitle;
  final bool isOccupied;
  final String occupancyPrimary;
  final String occupancySubtitle;
  final String rentalValueLabel;
  final String rentalValue;
  final String propertyId;
  final VoidCallback? onOccupancyTap;
  final VoidCallback? onRentalValueTap;

  const _HeroCard({
    required this.propertyName,
    required this.subtitle,
    required this.isOccupied,
    required this.occupancyPrimary,
    required this.occupancySubtitle,
    required this.rentalValueLabel,
    required this.rentalValue,
    required this.propertyId,
    this.onOccupancyTap,
    this.onRentalValueTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [
            PropertyDashboardTabScreen._heroStart,
            PropertyDashboardTabScreen._heroEnd,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: PropertyDashboardTabScreen._heroEnd.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.15),
                        image: const DecorationImage(
                          image: AssetImage('assets/images/login_bg.png'),
                          fit: BoxFit.cover,
                          opacity: 0.85,
                        ),
                      ),
                      child: Icon(
                        Icons.apartment_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            propertyName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isOccupied
                                        ? const Color(0xFF4ADE80)
                                        : Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isOccupied ? 'Occupied' : 'Vacant',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => showPropertySwitcherSheet(
                    context,
                    ref,
                    currentPropertyId: propertyId,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'All Properties',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withValues(alpha: 0.95),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    primary: occupancyPrimary,
                    secondary: occupancySubtitle,
                    onTap: onOccupancyTap,
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                Expanded(
                  child: _HeroStat(
                    primary: rentalValue,
                    secondary: rentalValueLabel,
                    onTap: onRentalValueTap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String primary;
  final String secondary;
  final VoidCallback? onTap;

  const _HeroStat({
    required this.primary,
    required this.secondary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(
          primary,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          secondary,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: content,
        ),
      ),
    );
  }
}

class _PrimaryQuickActionsRow extends StatelessWidget {
  final VoidCallback onAddTenant;
  final VoidCallback onNewInvoice;
  final VoidCallback onAddExpense;

  const _PrimaryQuickActionsRow({
    required this.onAddTenant,
    required this.onNewInvoice,
    required this.onAddExpense,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PrimaryActionChip(
            icon: Icons.person_add_alt_1_outlined,
            label: 'Add Tenant',
            color: AppColors.blueprint,
            onTap: onAddTenant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PrimaryActionChip(
            icon: Icons.receipt_outlined,
            label: 'New Invoice',
            color: PropertyDashboardTabScreen._brandPurple,
            onTap: onNewInvoice,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PrimaryActionChip(
            icon: Icons.add_card_outlined,
            label: 'Add Expense',
            color: const Color(0xFF16A34A),
            onTap: onAddExpense,
          ),
        ),
      ],
    );
  }
}

class _PrimaryActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PrimaryActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.grey.shade200,
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(
        color: PropertyDashboardTabScreen._brandPurple,
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: List.generate(
        6,
        (_) => Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 18,
          width: 140,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(height: 28),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ],
    );
  }
}

class _DashboardError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DashboardError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 40, color: AppColors.slate),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.slate, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: PropertyDashboardTabScreen._brandPurple,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetProfitStrip extends StatelessWidget {
  final double collected;
  final double expenses;
  final double netProfit;
  final String Function(num) formatCurrency;
  final VoidCallback? onCollectedTap;
  final VoidCallback? onExpensesTap;

  const _NetProfitStrip({
    required this.collected,
    required this.expenses,
    required this.netProfit,
    required this.formatCurrency,
    this.onCollectedTap,
    this.onExpensesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ProfitMetricCard(
                label: 'Collected This Month',
                value: formatCurrency(collected),
                valueColor: AppColors.positive,
                bg: const Color(0xFFDCFCE7),
                onTap: onCollectedTap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfitMetricCard(
                label: 'Expenses This Month',
                value: formatCurrency(expenses),
                valueColor: AppColors.danger,
                bg: const Color(0xFFFEE2E2),
                onTap: onExpensesTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ProfitMetricCard(
          label: 'Net Profit',
          value: formatCurrency(netProfit),
          valueColor: netProfit >= 0
              ? PropertyDashboardTabScreen._brandPurple
              : AppColors.danger,
          bg: const Color(0xFFEDE9FE),
          large: true,
        ),
      ],
    );
  }
}

class _ProfitMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color bg;
  final bool large;
  final VoidCallback? onTap;

  const _ProfitMetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.bg,
    this.large = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: large ? 16 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: large ? 13 : 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: large ? 26 : 18,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final String sublabel;
  final VoidCallback? onTap;

  const _OverviewCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.sublabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.slate,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              Text(
                sublabel,
                style: const TextStyle(fontSize: 10, color: AppColors.slate),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Actionable insights ---

class _InsightAlert {
  final String message;
  final bool isUrgent;
  final _InsightAlertType type;

  const _InsightAlert({
    required this.message,
    this.isUrgent = false,
    this.type = _InsightAlertType.kyc,
  });
}

enum _InsightAlertType { kyc, maintenance }

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    );
  }
}

class _NeedsAttentionSection extends StatelessWidget {
  final List<_InsightAlert> alerts;
  final VoidCallback? onKycTap;
  final VoidCallback? onMaintenanceTap;

  const _NeedsAttentionSection({
    required this.alerts,
    this.onKycTap,
    this.onMaintenanceTap,
  });

  VoidCallback? _tapFor(_InsightAlert alert) {
    switch (alert.type) {
      case _InsightAlertType.kyc:
        return onKycTap;
      case _InsightAlertType.maintenance:
        return onMaintenanceTap;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: alerts.map((alert) {
        final bg = alert.isUrgent
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF9C3);
        final border = alert.isUrgent
            ? const Color(0xFFFECACA)
            : const Color(0xFFFDE68A);
        final icon = alert.isUrgent ? '🚨' : '⚠️';
        final onTap = _tapFor(alert);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          alert.message,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: alert.isUrgent
                                ? const Color(0xFF991B1B)
                                : const Color(0xFF854D0E),
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          color: alert.isUrgent
                              ? const Color(0xFF991B1B)
                              : const Color(0xFF854D0E),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RentDefaultersSection extends StatelessWidget {
  final List<DashboardDefaulter> defaulters;

  const _RentDefaultersSection({required this.defaulters});

  String _formatCurrency(double value) => '₹${value.toStringAsFixed(0)}';

  void _sendReminder(BuildContext context, DashboardDefaulter d) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment reminder sent to ${d.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (defaulters.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Text(
          'No rent defaulters — all caught up!',
          style: TextStyle(color: AppColors.slate),
        ),
      );
    }

    final top = defaulters.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFFEE2E2),
                child: Text(
                  top[i].name.isNotEmpty ? top[i].name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                top[i].name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(
                '${top[i].unitDetails.isNotEmpty ? top[i].unitDetails : top[i].room} · ${_formatCurrency(top[i].amountDue)} due',
                style: const TextStyle(fontSize: 12, color: AppColors.slate),
              ),
              trailing: IconButton(
                tooltip: 'In-app remind',
                onPressed: () => _sendReminder(context, top[i]),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PropertyDashboardTabScreen._brandPurple
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: PropertyDashboardTabScreen._brandPurple,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingVacanciesCard extends StatelessWidget {
  final int noticeCount;

  const _UpcomingVacanciesCard({required this.noticeCount});

  @override
  Widget build(BuildContext context) {
    if (noticeCount == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryMuted),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Text(
          'No upcoming vacancies in the next 30 days.',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
            height: 1.35,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryMuted),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FE),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('🚪', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '🚪 $noticeCount Tenant${noticeCount == 1 ? '' : 's'} moving out in 30 days',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
