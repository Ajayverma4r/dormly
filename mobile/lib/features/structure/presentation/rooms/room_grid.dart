// features/structure/presentation/rooms/room_grid.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'rooms_tree_provider.dart';

class RoomOccupancySummary {
  final int total;
  final int occupied;

  const RoomOccupancySummary({required this.total, required this.occupied});

  int get available => total - occupied;

  bool get isFullyVacant => occupied == 0;

  bool get isFullyOccupied => total > 0 && available == 0;

  static RoomOccupancySummary fromNode(RoomsTreeNode node) {
    if (node.hasBedChildren) {
      final total = node.totalBeds > 0 ? node.totalBeds : node.children.length;
      final occupied = node.totalBeds > 0
          ? node.occupiedBeds
          : node.children.where((b) => b.occupied).length;
      return RoomOccupancySummary(total: total, occupied: occupied);
    }

    if (node.isAssignable && node.children.isEmpty) {
      return RoomOccupancySummary(
        total: 1,
        occupied: node.occupied ? 1 : 0,
      );
    }

    var total = 0;
    var occupied = 0;
    for (final child in node.children) {
      final s = fromNode(child);
      total += s.total;
      occupied += s.occupied;
    }
    if (total == 0 && node.isAssignable) {
      return RoomOccupancySummary(
        total: 1,
        occupied: node.occupied ? 1 : 0,
      );
    }
    return RoomOccupancySummary(total: total, occupied: occupied);
  }
}

Color roomStatusDotColor(RoomOccupancySummary summary) {
  if (summary.isFullyVacant) return Colors.green.shade600;
  if (summary.isFullyOccupied) return Colors.red.shade400;
  return Colors.grey.shade500;
}

int countRoomsOnFloor(RoomsTreeNode floorNode) => floorNode.children.length;

RoomsTreeNode? findTreeNodeById(List<RoomsTreeNode> nodes, String id) {
  for (final node in nodes) {
    if (node.id == id) return node;
    final found = findTreeNodeById(node.children, id);
    if (found != null) return found;
  }
  return null;
}

Widget buildRoomGrid(
  BuildContext context,
  List<RoomsTreeNode> rooms,
  Future<void> Function(RoomsTreeNode) onOpenRoom,
) {
  final tileWidth = MediaQuery.sizeOf(context).width / 3 - 24;

  return Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.start,
    children: [
      for (final room in rooms)
        SizedBox(
          width: tileWidth,
          child: CompactRoomTile(
            width: tileWidth,
            node: room,
            onTap: () => onOpenRoom(room),
          ),
        ),
    ],
  );
}

class CompactRoomTile extends StatelessWidget {
  final double width;
  final RoomsTreeNode node;
  final VoidCallback onTap;

  const CompactRoomTile({
    super.key,
    required this.width,
    required this.node,
    required this.onTap,
  });

  static const _secondaryStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.black54,
  );

  Widget _secondaryRow({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade800),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _secondaryStyle.copyWith(color: Colors.grey.shade800),
          ),
        ),
      ],
    );
  }

  bool _showBedCount(RoomOccupancySummary summary) {
    return node.hasBedChildren || summary.total > 1;
  }

  Widget? _buildSecondaryLine(RoomOccupancySummary summary) {
    final tenant = node.tenantDisplayName?.trim();

    // Condition 1: single-tenant display (flat, or single-bed room).
    if (tenant != null && tenant.isNotEmpty) {
      return _secondaryRow(icon: Icons.person, label: tenant);
    }

    // Condition 2: multi-bed occupancy fraction.
    if (_showBedCount(summary)) {
      return _secondaryRow(
        icon: Icons.bed,
        label: '${summary.occupied}/${summary.total} Beds',
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final summary = RoomOccupancySummary.fromNode(node);
    final dotColor = roomStatusDotColor(summary);
    final secondaryLine = _buildSecondaryLine(summary);

    final backgroundColor = summary.isFullyVacant
        ? Colors.green.shade50.withValues(alpha: 0.4)
        : summary.isFullyOccupied
            ? Colors.red.shade50.withValues(alpha: 0.35)
            : Colors.grey.shade50;
    final borderColor = summary.isFullyVacant
        ? Colors.green.shade200
        : summary.isFullyOccupied
            ? Colors.red.shade200
            : Colors.grey.shade300;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.ink,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (secondaryLine != null) ...[
                    const SizedBox(height: 6),
                    secondaryLine,
                  ],
                ],
              ),
              Positioned(
                top: 2,
                right: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.35),
                        blurRadius: 3,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
