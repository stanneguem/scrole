import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CommunitySalonCityPickerScreen extends StatefulWidget {
  const CommunitySalonCityPickerScreen({
    super.key,
    required this.options,
    required this.initialSelectedIds,
  });

  final List<Map<String, dynamic>> options;
  final List<String> initialSelectedIds;

  @override
  State<CommunitySalonCityPickerScreen> createState() =>
      _CommunitySalonCityPickerScreenState();
}

class _CommunitySalonCityPickerScreenState
    extends State<CommunitySalonCityPickerScreen> {
  late final Set<String> _selected;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelectedIds.toSet();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final visible = widget.options.where((city) {
      final name = (city['nom'] ?? '').toString().toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('salon_access_cities_title'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
            child: Text('salon_access_done'.tr),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'salon_access_search_city'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Text(
                  'salon_access_selected_count'.trParams({'count': _selected.length.toString()}),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(() => _selected.clear()),
                  child: Text('salon_access_clear'.tr),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text('salon_access_no_city'.tr))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 68,
                      color: colors.outlineVariant.withOpacity(.35),
                    ),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final id = item['id'].toString();
                      final selected = _selected.contains(id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
                        secondary: CircleAvatar(
                          backgroundColor: colors.surfaceContainerHighest,
                          child: Icon(Icons.location_city_outlined, color: colors.onSurfaceVariant),
                        ),
                        title: Text(
                          (item['nom'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
