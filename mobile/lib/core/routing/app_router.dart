// core/routing/app_router.dart
//
// Redirect rule implements: existing users never see onboarding again.
// The "has properties" check always comes from the server response, never
// a locally cached boolean, so it can't get out of sync.

import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/phone_login_screen.dart';
import '../../features/auth/presentation/otp_verify_screen.dart';
import '../../features/properties/presentation/empty_dashboard_screen.dart';
import '../../features/properties/presentation/property_wizard_screen.dart';
import '../../features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart';
import '../../features/properties/presentation/welcome_screen.dart';
import '../../features/structure/presentation/structure_editor/structure_editor_screen.dart';
import '../../features/properties/presentation/properties_list_screen.dart';
import '../../features/auth/presentation/context_picker_screen.dart';
import '../../features/auth/presentation/profile_creation_screen.dart';
import '../../features/tenant_portal/presentation/tenant_dashboard_screen.dart';
import '../../features/staff/presentation/invitations_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/home/presentation/profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const PhoneLoginScreen()),
    GoRoute(
      path: '/otp',
      builder: (context, state) => OtpVerifyScreen(phone: state.extra as String? ?? ''),
    ),
    GoRoute(
      path: '/onboarding/profile',
      builder: (context, state) => const ProfileCreationScreen(fromOnboarding: true),
    ),
    GoRoute(path: '/onboarding/welcome', builder: (context, state) => const WelcomeScreen()),
    GoRoute(path: '/onboarding/create-property', builder: (context, state) => const PropertyWizardScreen()),
    GoRoute(path: '/dashboard/empty', builder: (context, state) => const EmptyDashboardScreen()),

    // Primary property shell — ONLY the new 5-tab nav:
    // Dashboard | Tenants | Payments | Rooms | Menu
    // DynamicDashboardScreen → PropertyShellScreen (staff → Complaints only).
    GoRoute(
      path: '/property/:propertyId',
      builder: (context, state) => DynamicDashboardScreen(
        propertyId: state.pathParameters['propertyId']!,
        propertyName: (state.extra as Map?)?['propertyName'] ?? 'Dashboard',
      ),
    ),

    // Legacy deep-link alias — kept so any existing push('/dashboard/:id') calls
    // still work without a breaking change.
    GoRoute(
      path: '/dashboard/:propertyId',
      builder: (context, state) => DynamicDashboardScreen(
        propertyId: state.pathParameters['propertyId']!,
        propertyName: (state.extra as Map?)?['propertyName'] ?? 'Dashboard',
      ),
    ),

    GoRoute(
      path: '/dashboard/:propertyId/structure',
      builder: (context, state) => StructureEditorScreen(
        propertyId: state.pathParameters['propertyId']!,
      ),
    ),

    GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
    GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),

    // /home is the property picker for owners with multiple properties.
    GoRoute(path: '/home', builder: (context, state) => const PropertiesListScreen()),
    GoRoute(path: '/properties', builder: (context, state) => const PropertiesListScreen()),

    GoRoute(
      path: '/select-context',
      builder: (context, state) => ContextPickerScreen(
        contexts: state.extra as List<Map<String, dynamic>>,
      ),
    ),
    GoRoute(
      path: '/invitations',
      builder: (context, state) => InvitationsScreen(
        invitations: state.extra as List<Map<String, dynamic>>,
      ),
    ),

    GoRoute(path: '/tenant/dashboard', builder: (context, state) => const TenantDashboardScreen()),
  ],
);
