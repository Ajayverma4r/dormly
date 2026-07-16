// features/properties/presentation/empty_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmptyDashboardScreen extends StatelessWidget {
  const EmptyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Dormly', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 22)),
        actions: const [Padding(padding: EdgeInsets.only(right: 16), child: Icon(Icons.notifications_outlined, color: Colors.black87))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Welcome 👋', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text("Let's build your workspace.", style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.apartment, color: Color(0xFF2B5CFF), size: 32),
                const SizedBox(height: 12),
                const Text('Workspace Ready', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text("You haven't created any property yet.", style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B5CFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => context.push('/onboarding/create-property'),
                    child: const Text('Create First Property', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.3,
            children: const [
              _QuickActionCard(icon: Icons.home_work_outlined, label: 'Properties'),
              _QuickActionCard(icon: Icons.meeting_room_outlined, label: 'Rooms'),
              _QuickActionCard(icon: Icons.bed_outlined, label: 'Beds'),
              _QuickActionCard(icon: Icons.people_outline, label: 'Residents'),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  const _QuickActionCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF2B5CFF), size: 30),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}