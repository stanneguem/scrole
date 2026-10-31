import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CommunitySalonCountryPickerScreen extends StatefulWidget {
  const CommunitySalonCountryPickerScreen({
    super.key,
    required this.options,
    required this.initialSelectedIds,
  });

  final List<Map<String, dynamic>> options;
  final List<String> initialSelectedIds;

  @override
  State<CommunitySalonCountryPickerScreen> createState() =>
      _CommunitySalonCountryPickerScreenState();
}

class _CommunitySalonCountryPickerScreenState
    extends State<CommunitySalonCountryPickerScreen> {
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
    final visible = widget.options.where((country) {
      final name = (country['nom'] ?? '').toString().toLowerCase();
      final code = (country['code_iso'] ?? '').toString().toLowerCase();
      return query.isEmpty || name.contains(query) || code.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('salon_access_countries_title'.tr),
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
                hintText: 'salon_access_search_country'.tr,
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
                ? Center(child: Text('salon_access_no_country'.tr))
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
                      final name = (item['nom'] ?? '').toString();
                      final code = (item['code_iso'] ?? '').toString();
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
                          child: Text(
                            code.isEmpty ? (name.isEmpty ? '?' : name.substring(0, 1)) : code,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
