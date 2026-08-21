// features/auth/domain/user_profile.dart

class UserProfile {
  final String id;
  final String phone;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final bool profileComplete;
  final int propertyCount;
  final String? organizationId;
  final String? planSlug;
  final String? planName;
  final String? subscriptionStatus;

  const UserProfile({
    required this.id,
    required this.phone,
    this.name,
    this.email,
    this.avatarUrl,
    required this.profileComplete,
    required this.propertyCount,
    this.organizationId,
    this.planSlug,
    this.planName,
    this.subscriptionStatus,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      name: json['name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String? ?? json['avatar_url'] as String?,
      profileComplete: json['profileComplete'] as bool? ??
          ((json['name'] as String?)?.trim().isNotEmpty ?? false),
      propertyCount: (json['propertyCount'] as num?)?.toInt() ?? 0,
      organizationId: json['organizationId'] as String?,
      planSlug: json['planSlug'] as String?,
      planName: json['planName'] as String?,
      subscriptionStatus: json['subscriptionStatus'] as String?,
    );
  }

  String get displayPlan {
    if (planName != null && planName!.isNotEmpty) return planName!;
    if (planSlug == null || planSlug == 'free') return 'Free';
    return planSlug!.replaceAll('_', ' ');
  }
}
