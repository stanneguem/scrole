import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community_chat_group_country_picker_screen.dart';
import 'community_chat_group_city_picker_screen.dart';

class CommunityChatGroupAccessRulesScreen extends StatefulWidget {
  const CommunityChatGroupAccessRulesScreen({
    super.key,
    required this.salonId,
    required this.initialData,
  });

  final String salonId;
  final Map<String, dynamic> initialData;

  @override
  State<CommunityChatGroupAccessRulesScreen> createState() =>
      _CommunityChatGroupAccessRulesScreenState();
}

class _CommunityChatGroupAccessRulesScreenState
    extends State<CommunityChatGroupAccessRulesScreen> {
  final _db = Supabase.instance.client;
  final _minAge = TextEditingController();
  final _maxAge = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _countriesEnabled = false;
  bool _citiesEnabled = false;
  bool _certification = false;
  bool _parentCountriesEnabled = false;
  bool _parentCitiesEnabled = false;
  bool _parentCertification = false;
  List<String> _countries = [];
  List<String> _cities = [];
  List<String> _parentCountries = [];
  List<String> _parentCities = [];
  List<Map<String, dynamic>> _countryOptions = [];
  List<Map<String, dynamic>> _cityOptions = [];
  String? _gender;
  String? _parentGender;
  int? _parentAgeMin;
  int? _parentAgeMax;

  Map<String, dynamic> get _rules =>
      Map<String, dynamic>.from(widget.initialData['access_rules'] ?? {});

  @override
  void initState() {
    super.initState();
    _countriesEnabled = _rules['countries_enabled'] == true;
    _citiesEnabled = _rules['cities_enabled'] == true;
    _certification = _rules['certification_required'] == true;
    _countries = List<String>.from(_rules['allowed_countries'] ?? []);
    _cities = List<String>.from(_rules['allowed_cities'] ?? []);
    _gender = _rules['gender_restriction']?.toString();
    _minAge.text = _rules['age_min']?.toString() ?? '';
    _maxAge.text = _rules['age_max']?.toString() ?? '';
    _loadOptions();
  }

  @override
  void dispose() {
    _minAge.dispose();
    _maxAge.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final parentRaw = await _db.rpc(
        'get_community_chat_group_parent_access_rules',
        params: {'p_salon_id': widget.salonId},
      );
      final parent = Map<String, dynamic>.from(parentRaw as Map);

      final countryResponse = await _db
          .from('countries')
          .select('id,nom,code_iso')
          .eq('is_active', true)
          .order('nom');
      final cityResponse = await _db
          .from('cities')
          .select('id,nom,country_id')
          .eq('is_active', true)
          .order('nom');

      if (!mounted) return;
      _parentCountriesEnabled = parent['countries_enabled'] == true;
      _parentCitiesEnabled = parent['cities_enabled'] == true;
      _parentCountries = List<String>.from(parent['allowed_countries'] ?? []);
      _parentCities = List<String>.from(parent['allowed_cities'] ?? []);
      _parentCertification = parent['certification_required'] == true;
      _parentGender = parent['gender_restriction']?.toString();
      _parentAgeMin = (parent['age_min'] as num?)?.toInt();
      _parentAgeMax = (parent['age_max'] as num?)?.toInt();

      final allCountries = (countryResponse as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final allCities = (cityResponse as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _allCityOptions = allCities;

      _countryOptions = _parentCountriesEnabled
          ? allCountries.where((e) => _parentCountries.contains(e['id'].toString())).toList()
          : allCountries;

      _cityOptions = allCities.where((city) {
        final cityId = city['id'].toString();
        final countryId = city['country_id']?.toString();
        if (_parentCitiesEnabled && !_parentCities.contains(cityId)) return false;
        if (_parentCountriesEnabled && !_parentCountries.contains(countryId)) return false;
        if (_countriesEnabled && !_countries.contains(countryId)) return false;
        return true;
      }).toList();

      // Keep only selections still allowed by the parent community.
      final availableCountryIds = _countryOptions.map((e) => e['id'].toString()).toSet();
      final availableCityIds = _cityOptions.map((e) => e['id'].toString()).toSet();
      _countries = _countries.where(availableCountryIds.contains).toList();
      _cities = _cities.where(availableCityIds.contains).toList();

      // A parent restriction is inherited by default and cannot be removed by a salon.
      if (_parentCountriesEnabled) {
        _countriesEnabled = true;
        if (_countries.isEmpty) _countries = List<String>.from(_parentCountries);
      }
      if (_parentCitiesEnabled) {
        _citiesEnabled = true;
        if (_cities.isEmpty) _cities = List<String>.from(_parentCities);
      }
      _refreshCityOptions();

      if (_parentCertification) _certification = true;
      if (_parentGender != null) _gender = _parentGender;
      if (_parentAgeMin != null && _minAge.text.trim().isEmpty) _minAge.text = '$_parentAgeMin';
      if (_parentAgeMax != null && _maxAge.text.trim().isEmpty) _maxAge.text = '$_parentAgeMax';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('salon_access_load_error'.trParams({'error': e.toString()}));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _refreshCityOptions() {
    final selectedCountryIds = _countriesEnabled ? _countries.toSet() : <String>{};
    final parentCityIds = _parentCitiesEnabled ? _parentCities.toSet() : <String>{};
    final parentCountryIds = _parentCountriesEnabled ? _parentCountries.toSet() : <String>{};
    _cityOptions = _allCityOptions.where((city) {
      final id = city['id'].toString();
      final countryId = city['country_id']?.toString() ?? '';
      if (_parentCitiesEnabled && !parentCityIds.contains(id)) return false;
      if (_parentCountriesEnabled && !parentCountryIds.contains(countryId)) return false;
      if (_countriesEnabled && !selectedCountryIds.contains(countryId)) return false;
      return true;
    }).toList();
    final available = _cityOptions.map((e) => e['id'].toString()).toSet();
    _cities = _cities.where(available.contains).toList();
  }

  List<Map<String, dynamic>> _allCityOptions = [];

  Future<void> _chooseCountries() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => CommunitySalonCountryPickerScreen(
          options: _countryOptions,
          initialSelectedIds: _countries,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _countries = result;
      if (_countriesEnabled) _refreshCityOptions();
    });
  }

  Future<void> _chooseCities() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => CommunitySalonCityPickerScreen(
          options: _cityOptions,
          initialSelectedIds: _cities,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _cities = result);
  }

  Future<void> _save() async {
    final minText = _minAge.text.trim();
    final maxText = _maxAge.text.trim();
    final min = minText.isEmpty ? null : int.tryParse(minText);
    final max = maxText.isEmpty ? null : int.tryParse(maxText);

    if (minText.isNotEmpty && min == null || maxText.isNotEmpty && max == null) {
      _toast('salon_access_age_invalid'.tr);
      return;
    }
    if (min != null && (min < 13 || min > 120) ||
        max != null && (max < 13 || max > 120) ||
        min != null && max != null && min > max) {
      _toast('salon_access_age_range_invalid'.tr);
      return;
    }
    if (_parentAgeMin != null && (min == null || min < _parentAgeMin!)) {
      _toast('salon_access_parent_age_min'.trParams({'age': '$_parentAgeMin'}));
      return;
    }
    if (_parentAgeMax != null && (max == null || max > _parentAgeMax!)) {
      _toast('salon_access_parent_age_max'.trParams({'age': '$_parentAgeMax'}));
      return;
    }
    if (_countriesEnabled && _countries.isEmpty) {
      _toast('salon_access_select_country'.tr);
      return;
    }
    if (_citiesEnabled && _cities.isEmpty) {
      _toast('salon_access_select_city'.tr);
      return;
    }
    if (_parentCertification && !_certification) {
      _toast('salon_access_parent_certification'.tr);
      return;
    }
    if (_parentGender != null && _gender != _parentGender) {
      _toast('salon_access_parent_gender'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      await _db.rpc('update_community_chat_group_advanced_settings', params: {
        'p_salon_id': widget.salonId,
        'p_audio_messages_allowed': widget.initialData['audio_messages_allowed'] == true,
        'p_countries_enabled': _countriesEnabled,
        'p_allowed_countries': _countries,
        'p_cities_enabled': _citiesEnabled,
        'p_allowed_cities': _cities,
        'p_certification_required': _certification,
        'p_gender_restriction': _gender,
        'p_age_min': min,
        'p_age_max': max,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final raw = e.toString().toLowerCase();
      String message;
      if (raw.contains('propriétaire du salon') || raw.contains('owner')) {
        message = 'salon_access_owner_conflict'.tr;
      } else if (raw.contains('certification')) {
        message = 'salon_access_owner_certification_conflict'.tr;
      } else if (raw.contains('âge') || raw.contains('age')) {
        message = 'salon_access_owner_age_conflict'.tr;
      } else {
        message = 'salon_access_save_error'.trParams({'error': e.toString()});
      }
      _toast(message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _names(List<String> ids, List<Map<String, dynamic>> options) {
    final names = options
        .where((e) => ids.contains(e['id'].toString()))
        .map((e) => e['nom'].toString())
        .toList();
    return names.isEmpty
        ? 'salon_access_none_selected'.tr
        : names.length <= 2
            ? names.join(', ')
            : 'salon_access_selected_count'.trParams({'count': names.length.toString()});
  }

  Widget _restrictionSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    final enabled = value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(.32),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: enabled ? colors.primary.withOpacity(.28) : colors.outlineVariant.withOpacity(.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (enabled ? colors.primary : colors.onSurfaceVariant).withOpacity(.11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: enabled ? colors.primary : colors.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                )),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: _saving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _selectionTile({
    required IconData icon,
    required String title,
    required String summary,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: enabled && !_saving ? onTap : null,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        )),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(3, 20, 3, 10),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
    )),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('salon_access_title'.tr),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _loading || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('salon_access_save'.tr),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                Text(
                  'salon_access_intro'.tr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                _sectionTitle('salon_access_location_section'.tr),
                _restrictionSwitch(
                  icon: Icons.public_rounded,
                  title: 'salon_access_country_restriction'.tr,
                  subtitle: 'salon_access_country_description'.tr,
                  value: _countriesEnabled,
                  onChanged: _countryOptions.isEmpty && !_parentCountriesEnabled
                      ? null
                      : (value) {
                          if (_parentCountriesEnabled && !value) return;
                          setState(() {
                            _countriesEnabled = value;
                            _refreshCityOptions();
                          });
                        },
                ),
                const SizedBox(height: 9),
                _selectionTile(
                  icon: Icons.flag_outlined,
                  title: 'salon_access_choose_countries'.tr,
                  summary: _names(_countries, _countryOptions),
                  onTap: _chooseCountries,
                  enabled: _countriesEnabled,
                ),
                const SizedBox(height: 13),
                _restrictionSwitch(
                  icon: Icons.location_city_rounded,
                  title: 'salon_access_city_restriction'.tr,
                  subtitle: 'salon_access_city_description'.tr,
                  value: _citiesEnabled,
                  onChanged: _cityOptions.isEmpty && !_parentCitiesEnabled
                      ? null
                      : (value) {
                          if (_parentCitiesEnabled && !value) return;
                          setState(() => _citiesEnabled = value);
                        },
                ),
                const SizedBox(height: 9),
                _selectionTile(
                  icon: Icons.location_on_outlined,
                  title: 'salon_access_choose_cities'.tr,
                  summary: _names(_cities, _cityOptions),
                  onTap: _chooseCities,
                  enabled: _citiesEnabled,
                ),
                _sectionTitle('salon_access_profile_section'.tr),
                _restrictionSwitch(
                  icon: Icons.verified_user_outlined,
                  title: 'salon_access_certification'.tr,
                  subtitle: 'salon_access_certification_description'.tr,
                  value: _certification,
                  onChanged: _parentCertification
                      ? null
                      : (value) => setState(() => _certification = value),
                ),
                const SizedBox(height: 14),
                Text('salon_access_gender'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('salon_access_gender_any'.tr),
                      selected: _gender == null,
                      onSelected: _parentGender != null || _saving
                          ? null
                          : (_) => setState(() => _gender = null),
                    ),
                    ChoiceChip(
                      label: Text('salon_access_gender_men'.tr),
                      selected: _gender == 'homme',
                      onSelected: _parentGender != null || _saving
                          ? null
                          : (_) => setState(() => _gender = 'homme'),
                    ),
                    ChoiceChip(
                      label: Text('salon_access_gender_women'.tr),
                      selected: _gender == 'femme',
                      onSelected: _parentGender != null || _saving
                          ? null
                          : (_) => setState(() => _gender = 'femme'),
                    ),
                  ],
                ),
                if (_parentGender != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('salon_access_parent_gender'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      )),
                  ),
                _sectionTitle('salon_access_age_section'.tr),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minAge,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'salon_access_age_min'.tr,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxAge,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'salon_access_age_max'.tr,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_parentAgeMin != null || _parentAgeMax != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('salon_access_parent_age_hint'.trParams({
                      'min': _parentAgeMin?.toString() ?? '—',
                      'max': _parentAgeMax?.toString() ?? '—',
                    }), style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    )),
                  ),
              ],
            ),
    );
  }
}
