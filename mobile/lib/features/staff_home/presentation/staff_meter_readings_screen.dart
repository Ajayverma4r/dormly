// features/staff_home/presentation/staff_meter_readings_screen.dart
//
// Staff record electricity readings per unit. The server applies the
// property's own rate; staff never send or see a rate or amount.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../properties/domain/property_archetype.dart';
import '../../structure/presentation/rooms/rooms_tree_provider.dart';
import '../../tenant_portal/data/tenant_portal_repository.dart';
import '../domain/staff_rooms_summary.dart';
import 'staff_ui.dart';

final _day = DateFormat('d MMM yyyy');
final _num = NumberFormat('#,##0.###');

double? _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

/// Most recent reading per unit id (the list arrives newest first).
Map<String, Map<String, dynamic>> latestReadingByUnit(
    List<Map<String, dynamic>> readings) {
  final out = <String, Map<String, dynamic>>{};
  for (final r in readings) {
    final unit = r['unit_id']?.toString() ?? '';
    if (unit.isNotEmpty) out.putIfAbsent(unit, () => r);
  }
  return out;
}

/// Null when [input] is a valid next reading after [previous].
String? validateMeterReading(String input, double? previous) {
  final value = double.tryParse(input.trim());
  if (input.trim().isEmpty) return 'Enter the meter reading';
  if (value == null) return 'Enter a number, e.g. 1250.5';
  if (value <= 0) return 'Reading must be greater than 0';
  if (previous != null && value < previous) {
    return 'Must be at least the previous reading (${_num.format(previous)})';
  }
  return null;
}

/// App-side wording for the server's meter validation codes; the server's
/// own message is never shown.
const _meterErrorText = {
  'invalid_reading': 'Enter a reading greater than 0.',
  'reading_below_previous':
      'This reading is lower than the latest one on record. Someone may have '
          'just saved a newer reading. Refresh and check the meter.',
  'amount_out_of_range':
      'This reading is far higher than the last one. Check the meter and try again.',
  'invalid_rate':
      "This property's electricity rate needs checking. Ask a manager to review it.",
};

/// User-facing text for a failed reading submit.
String meterReadingErrorMessage(Object error) {
  if (error is DioException && error.response?.statusCode == 400) {
    final data = error.response?.data;
    final code = data is Map ? data['code'] : null;
    final known = _meterErrorText[code];
    if (known != null) return known;
  }
  return staffErrorMessage(error,
      fallback: 'Could not save the reading. Please try again.');
}

class StaffMeterReadingsScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const StaffMeterReadingsScreen({super.key, required this.propertyId});

  @override
  ConsumerState<StaffMeterReadingsScreen> createState() =>
      _StaffMeterReadingsScreenState();
}

class _StaffMeterReadingsScreenState
    extends ConsumerState<StaffMeterReadingsScreen> {
  String _query = '';

  Future<void> _refresh() async {
    ref.invalidate(roomsTreeProvider(widget.propertyId));
    await ref
        .refresh(staffMeterReadingsProvider(widget.propertyId).future)
        .then<void>((_) {}, onError: (_) {});
  }

  Future<void> _enterReading(StaffRoom unit, Map<String, dynamic>? last) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReadingSheet(
        propertyId: widget.propertyId,
        unit: unit,
        previous: _asDouble(last?['meter_reading_value']),
      ),
    );
    if (saved == true && mounted) {
      ref.invalidate(staffMeterReadingsProvider(widget.propertyId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reading saved for ${unit.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final archetype = staffPropertyArchetype(ref, widget.propertyId);
    const appBar = StaffAppBar(title: 'Meter Readings');

    if (archetype != null && !archetype.showsMeterUpload) {
      return const Scaffold(
        backgroundColor: StaffColors.bg,
        appBar: appBar,
        body: StaffMessage(
          key: Key('staff-meters-unsupported'),
          icon: Icons.speed_outlined,
          title: 'Meter readings are not used here',
          subtitle:
              'Electricity readings are recorded for flats and rental units.',
        ),
      );
    }

    final roomsAsync = ref.watch(roomsTreeProvider(widget.propertyId));
    final readingsAsync =
        ref.watch(staffMeterReadingsProvider(widget.propertyId));

    Widget body;
    if (roomsAsync.hasError || readingsAsync.hasError) {
      body = StaffScrollableMessage(
        child: StaffErrorState(
          key: const Key('staff-meters-error'),
          error: (roomsAsync.error ?? readingsAsync.error)!,
          fallback: "Couldn't load meter readings. Please try again.",
          onRetry: _refresh,
        ),
      );
    } else if (!roomsAsync.hasValue || !readingsAsync.hasValue) {
      body = const Center(
          child: CircularProgressIndicator(color: StaffColors.brand));
    } else {
      final units = summarizeRooms(roomsAsync.value!).rooms;
      final latest = latestReadingByUnit(readingsAsync.value!);
      final q = _query.trim().toLowerCase();
      final visible = q.isEmpty
          ? units
          : units
              .where((u) =>
                  u.name.toLowerCase().contains(q) ||
                  u.section.toLowerCase().contains(q))
              .toList();

      body = units.isEmpty
          ? const StaffScrollableMessage(
              child: StaffMessage(
                key: Key('staff-meters-empty'),
                icon: Icons.speed_outlined,
                title: 'No units to read yet',
                subtitle:
                    'Units appear here once the owner or manager adds them.',
              ),
            )
          : ListView(
              key: const Key('staff-meters-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                TextField(
                  key: const Key('staff-meters-search'),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search unit',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: StaffColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: StaffColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: StaffMessage(
                        icon: Icons.search_off_rounded,
                        title: 'No units match'),
                  )
                else
                  for (final u in visible) ...[
                    _MeterCard(
                      unit: u,
                      last: latest[u.id],
                      onEnter: () => _enterReading(u, latest[u.id]),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
    }

    return Scaffold(
      backgroundColor: StaffColors.bg,
      appBar: appBar,
      body: RefreshIndicator(
          color: StaffColors.brand, onRefresh: _refresh, child: body),
    );
  }
}

class _MeterCard extends StatelessWidget {
  final StaffRoom unit;
  final Map<String, dynamic>? last;
  final VoidCallback onEnter;

  const _MeterCard(
      {required this.unit, required this.last, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    final value = _asDouble(last?['meter_reading_value']);
    final used = _asDouble(last?['units_consumed']);
    final date =
        DateTime.tryParse(last?['created_at']?.toString() ?? '')?.toLocal();

    return Container(
      key: Key('staff-meter-${unit.id}'),
      decoration: staffCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: StaffColors.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.speed_rounded, color: StaffColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: StaffColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                if (unit.section.isNotEmpty)
                  Text(
                    unit.section,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: StaffColors.muted, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Text(
                  value == null
                      ? 'No reading yet'
                      : 'Last: ${_num.format(value)}'
                          '${used != null && used > 0 ? ' (+${_num.format(used)})' : ''}'
                          '${date != null ? ' · ${_day.format(date)}' : ''}',
                  key: Key('staff-meter-last-${unit.id}'),
                  style:
                      const TextStyle(color: StaffColors.ink, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: Key('staff-meter-enter-${unit.id}'),
            onPressed: onEnter,
            style: FilledButton.styleFrom(
              backgroundColor: StaffColors.brand,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Enter'),
          ),
        ],
      ),
    );
  }
}

class _ReadingSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final StaffRoom unit;
  final double? previous;

  const _ReadingSheet(
      {required this.propertyId, required this.unit, required this.previous});

  @override
  ConsumerState<_ReadingSheet> createState() => _ReadingSheetState();
}

class _ReadingSheetState extends ConsumerState<_ReadingSheet> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final problem = validateMeterReading(_controller.text, widget.previous);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(tenantPortalRepositoryProvider)
          .submitMeterReadingForProperty(
            propertyId: widget.propertyId,
            unitId: widget.unit.id,
            readingValue: double.parse(_controller.text.trim()),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = meterReadingErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prev = widget.previous;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New reading · ${widget.unit.name}',
            style: const TextStyle(
                color: StaffColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            prev == null
                ? 'No previous reading'
                : 'Previous reading: ${_num.format(prev)}',
            key: const Key('staff-meter-previous'),
            style: const TextStyle(color: StaffColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('staff-meter-input'),
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Current reading',
              errorText: _error,
              errorMaxLines: 3,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const Key('staff-meter-save'),
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: StaffColors.brand,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save reading'),
            ),
          ),
        ],
      ),
    );
  }
}
