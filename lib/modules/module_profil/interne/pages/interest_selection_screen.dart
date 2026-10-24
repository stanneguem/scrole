import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/models/interest_model.dart';

class InterestSelectionScreen extends StatefulWidget {
  const InterestSelectionScreen({super.key});

  @override
  State<InterestSelectionScreen> createState() => _InterestSelectionScreenState();
}

class _InterestSelectionScreenState extends State<InterestSelectionScreen> {
  late final List<Interest> allInterests;
  late final Set<String> currentSelectedIds;
  late final int maxSelection;
  
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';
  String? selectedCategory;

  @override
  void initState() {
    super.initState();
    final args = (Get.arguments is Map) ? Map<String, dynamic>.from(Get.arguments as Map) : <String, dynamic>{};
    allInterests = List<Interest>.from(args['allInterests'] ?? []);
    final initialIds = List<String>.from(args['selectedIds'] ?? []);
    currentSelectedIds = Set<String>.from(initialIds);
    maxSelection = (args['maxSelection'] as int?) ?? 0;

    searchController.addListener(() {
      if (mounted) {
        setState(() {
          searchQuery = searchController.text.trim();
        });
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Interest> get filteredInterests {
    return allInterests.where((interest) {
      final matchesSearch = searchQuery.isEmpty || interest.name.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesCategory = selectedCategory == null || interest.category == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  List<Interest> get categoryInterests {
    return allInterests.where((interest) {
      final matchesCategory = selectedCategory == null || interest.category == selectedCategory;
      return matchesCategory;
    }).toList();
  }

  List<String> get categories {
    final cats = allInterests.map((e) => e.category).whereType<String>().toSet().toList();
    cats.sort();
    return cats;
  }

  bool get areAllCategorySelected {
    final targetList = searchQuery.isNotEmpty ? filteredInterests : categoryInterests;
    if (targetList.isEmpty) return false;
    return targetList.every((i) => currentSelectedIds.contains(i.id));
  }

  void _toggleSelectAllCategory() {
    final targetList = searchQuery.isNotEmpty ? filteredInterests : categoryInterests;
    if (targetList.isEmpty) return;

    setState(() {
      if (areAllCategorySelected) {
        // Tout désélectionner
        for (final item in targetList) {
          currentSelectedIds.remove(item.id);
        }
      } else {
        // Tout sélectionner
        if (maxSelection <= 0) {
          for (final item in targetList) {
            currentSelectedIds.add(item.id);
          }
        } else {
          for (final item in targetList) {
            if (currentSelectedIds.length < maxSelection) {
              currentSelectedIds.add(item.id);
            } else {
              Get.snackbar(
                'Limitation',
                'interests_limit_reached'.tr,
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.orange,
                colorText: Colors.white,
              );
              break;
            }
          }
        }
      }
    });
  }

  void _toggleInterest(String id) {
    setState(() {
      if (currentSelectedIds.contains(id)) {
        currentSelectedIds.remove(id);
      } else {
        if (maxSelection <= 0 || currentSelectedIds.length < maxSelection) {
          currentSelectedIds.add(id);
        } else {
          Get.snackbar(
            'Limitation',
            'interests_limit_reached'.tr,
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
        }
      }
    });
  }

  Widget _buildCategoryPill(String label, bool isSelected, VoidCallback onTap) {
    final isDark = Get.isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.surfaceDark : Colors.grey[200]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.border : Colors.transparent),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final colors = Theme.of(context).colorScheme;
    final filtered = filteredInterests;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          'interests_title'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Get.back(result: currentSelectedIds.toList()),
              child: Text(
                'Valider (${currentSelectedIds.length})',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: TextField(
              controller: searchController,
              style: AppTextStyles.input.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher un centre d\'intérêt...',
                hintStyle: AppTextStyles.inputHint.copyWith(
                  color: AppColors.textSecondary,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          searchController.clear();
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : colors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Sélecteur de catégories
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildCategoryPill('interests_all'.tr, selectedCategory == null, () {
                  setState(() => selectedCategory = null);
                }),
                ...categories.map((cat) => _buildCategoryPill(cat, selectedCategory == cat, () {
                  setState(() => selectedCategory = cat);
                })),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // En-tête de catégorie + Bouton Tout sélectionner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedCategory ?? 'Tous les centres d\'intérêt',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.1),
                ),
                if (filtered.isNotEmpty)
                  InkWell(
                    onTap: _toggleSelectAllCategory,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        areAllCategorySelected ? 'Tout désélectionner' : 'Tout sélectionner',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Grille 2 colonnes ou état vide
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off_rounded, size: 48, color: AppColors.disabled),
                          const SizedBox(height: 12),
                          Text(
                            'Aucun centre d\'intérêt trouvé',
                            style: AppTextStyles.h4,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Essayez de modifier votre recherche ou changez de catégorie.',
                            style: AppTextStyles.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 2.8,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final interest = filtered[index];
                      final isSelected = currentSelectedIds.contains(interest.id);

                      return _InterestCard(
                        interest: interest,
                        isSelected: isSelected,
                        onTap: () => _toggleInterest(interest.id),
                      );
                    },
                  ),
          ),

          // Barre inférieure flottante de validation
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${currentSelectedIds.length} sélectionné${currentSelectedIds.length > 1 ? 's' : ''}',
                          style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (maxSelection > 0)
                          Text(
                            'Maximum $maxSelection',
                            style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Get.back(result: currentSelectedIds.toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Valider',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InterestCard extends StatelessWidget {
  final Interest interest;
  final bool isSelected;
  final VoidCallback onTap;

  const _InterestCard({
    required this.interest,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : (isDark ? AppColors.surfaceDark : colors.surfaceContainerLow),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : colors.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (interest.iconUrl != null && interest.iconUrl!.isNotEmpty) ...[
              Text(
                interest.iconUrl!,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                interest.name,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              color: isSelected ? AppColors.primary : colors.outline.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
