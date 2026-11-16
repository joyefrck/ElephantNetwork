// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show isWithin, join;

class ThemeModeItem {
  final ThemeMode themeMode;
  final IconData iconData;
  final String label;

  const ThemeModeItem({
    required this.themeMode,
    required this.iconData,
    required this.label,
  });
}

class FontFamilyItem {
  final FontFamily fontFamily;
  final String label;

  const FontFamilyItem({required this.fontFamily, required this.label});
}

class ThemeView extends StatelessWidget {
  const ThemeView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return BaseScaffold(
      title: appLocalizations.theme,
      body: const CustomScrollView(
        slivers: [
          _ThemeModeItem(),
          SliverToBoxAdapter(child: SizedBox(height: 16)),
          _ThemeSkinItem(),
          SliverToBoxAdapter(child: SizedBox(height: 16)),
          _SkinOpacityItem(),
          _TextScaleFactorItem(),
          SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final Widget child;
  final Info info;
  final List<Widget> actions;

  const ItemCard({
    super.key,
    required this.info,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 16,
      children: [
        InfoHeader(info: info, actions: actions),
        child,
      ],
    );
  }
}

class _ThemeModeItem extends ConsumerWidget {
  const _ThemeModeItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final themeMode = ref.watch(
      themeSettingProvider.select((state) => state.themeMode),
    );
    final List<ThemeModeItem> themeModeItems = [
      ThemeModeItem(
        iconData: Icons.auto_mode,
        label: appLocalizations.auto,
        themeMode: ThemeMode.system,
      ),
      ThemeModeItem(
        iconData: Icons.light_mode,
        label: appLocalizations.light,
        themeMode: ThemeMode.light,
      ),
      ThemeModeItem(
        iconData: Icons.dark_mode,
        label: appLocalizations.dark,
        themeMode: ThemeMode.dark,
      ),
    ];
    return SliverToBoxAdapter(
      child: ItemCard(
        info: Info(
          label: appLocalizations.themeMode,
          iconData: Icons.brightness_high,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: themeModeItems.length,
            itemBuilder: (_, index) {
              final themeModeItem = themeModeItems[index];
              return CommonCard(
                isSelected: themeModeItem.themeMode == themeMode,
                onPressed: () {
                  ref
                      .read(themeSettingProvider.notifier)
                      .update(
                        (state) =>
                            state.copyWith(themeMode: themeModeItem.themeMode),
                      );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Flexible(child: Icon(themeModeItem.iconData)),
                      const SizedBox(width: 8),
                      Flexible(child: Text(themeModeItem.label)),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) {
              return const SizedBox(width: 16);
            },
          ),
        ),
      ),
    );
  }
}

class _ThemeSkinItem extends ConsumerStatefulWidget {
  const _ThemeSkinItem();

  @override
  ConsumerState<_ThemeSkinItem> createState() => _ThemeSkinItemState();
}

class _ThemeSkinItemState extends ConsumerState<_ThemeSkinItem> {
  bool _isPicking = false;

  int _calcColumns(double maxWidth) {
    return max((maxWidth / 200).floor(), 2);
  }

  void _selectSkin(ThemeSkin skin) {
    ref.read(themeSettingProvider.notifier).update((state) {
      return switch (skin) {
        ThemeSkin.custom => state.copyWith(skin: skin),
        _ => state.copyWith(skin: skin, primaryColor: skin.seedColor),
      };
    });
  }

  Future<void> _pickImage() async {
    if (_isPicking) {
      return;
    }
    setState(() {
      _isPicking = true;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      final seed = await _seedColorOf(bytes);
      final path = await _storeImage(file.extension, bytes);
      final previous = ref.read(themeSettingProvider).skinImagePath;
      ref.read(themeSettingProvider.notifier).update((state) {
        return state.copyWith(
          skin: ThemeSkin.custom,
          skinImagePath: path,
          primaryColor: seed ?? state.primaryColor,
        );
      });
      if (previous != null && previous != path) {
        await _deleteStoredImage(previous);
      }
    } catch (_) {
      if (mounted) {
        context.showNotifier(context.appLocalizations.skinImageFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<int?> _seedColorOf(Uint8List bytes) async {
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(MemoryImage(bytes), width: 112, height: 112),
      );
      return scheme.primary.toARGB32();
    } catch (_) {
      return null;
    }
  }

  Future<String> _storeImage(String? extension, Uint8List bytes) async {
    final directory = Directory(join(await appPath.homeDirPath, 'theme'));
    await directory.create(recursive: true);
    final suffix = (extension == null || extension.isEmpty)
        ? 'img'
        : extension.toLowerCase();
    final path = join(
      directory.path,
      'skin_${DateTime.now().millisecondsSinceEpoch}.$suffix',
    );
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> _deleteStoredImage(String path) async {
    final directory = join(await appPath.homeDirPath, 'theme');
    if (!isWithin(directory, path)) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _handleTap(ThemeSkin skin, String? imagePath) {
    if (skin == ThemeSkin.custom && (imagePath == null || imagePath.isEmpty)) {
      _pickImage();
      return;
    }
    _selectSkin(skin);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final currentSkin = ref.watch(
      themeSettingProvider.select((state) => state.skin),
    );
    final imagePath = ref.watch(
      themeSettingProvider.select((state) => state.skinImagePath),
    );
    final customSeed = ref.watch(
      themeSettingProvider.select(
        (state) => state.skin == ThemeSkin.custom ? state.primaryColor : null,
      ),
    );
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    return SliverToBoxAdapter(
      child: ItemCard(
        info: Info(
          label: appLocalizations.themeSkin,
          iconData: Icons.wallpaper,
        ),
        actions: genActions([
          if (currentSkin == ThemeSkin.custom && hasImage)
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _isPicking ? null : _pickImage,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(appLocalizations.skinChangeImage),
            ),
        ], space: 8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final columns = _calcColumns(constraints.maxWidth);
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final skin in ThemeSkin.values)
                    SizedBox(
                      width: itemWidth,
                      child: ThemeSkinCard(
                        key: ValueKey('theme_skin_${skin.name}'),
                        skin: skin,
                        label: _skinLabel(appLocalizations, skin),
                        seedColor: switch (skin) {
                          ThemeSkin.custom =>
                            customSeed ?? defaultSkinSeedColor,
                          _ => skin.seedColor!,
                        },
                        imagePath: imagePath,
                        hint: skin == ThemeSkin.custom && !hasImage
                            ? appLocalizations.skinPickImage
                            : null,
                        isSelected:
                            currentSkin == skin &&
                            (skin != ThemeSkin.custom || hasImage),
                        onPressed: () => _handleTap(skin, imagePath),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _skinLabel(AppLocalizations appLocalizations, ThemeSkin skin) {
  return switch (skin) {
    ThemeSkin.none => appLocalizations.skinNone,
    ThemeSkin.crayon => appLocalizations.skinCrayon,
    ThemeSkin.ocean => appLocalizations.skinOcean,
    ThemeSkin.sakura => appLocalizations.skinSakura,
    ThemeSkin.starry => appLocalizations.skinStarry,
    ThemeSkin.kitty => appLocalizations.skinKitty,
    ThemeSkin.detective => appLocalizations.skinDetective,
    ThemeSkin.captain => appLocalizations.skinCaptain,
    ThemeSkin.lantern => appLocalizations.skinLantern,
    ThemeSkin.custom => appLocalizations.skinCustom,
  };
}

class ThemeSkinCard extends ConsumerWidget {
  final ThemeSkin skin;
  final String label;
  final int seedColor;
  final String? imagePath;
  final String? hint;
  final bool isSelected;
  final VoidCallback onPressed;

  const ThemeSkinCard({
    super.key,
    required this.skin,
    required this.label,
    required this.seedColor,
    required this.isSelected,
    required this.onPressed,
    this.imagePath,
    this.hint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final scheme = ref.watch(
      genColorSchemeProvider(brightness, color: Color(seedColor)),
    );
    final layer = ThemeSkinLayer(skin: skin, imagePath: imagePath);
    return CommonCard(
      isSelected: isSelected,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Theme(
                  data: Theme.of(context).copyWith(colorScheme: scheme),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: skin == ThemeSkin.none
                            ? BoxDecoration(
                                color: brightness == Brightness.light
                                    ? Colors.white
                                    : scheme.surface,
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              )
                            : BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.surfaceContainerLowest,
                                    scheme.primaryContainer,
                                  ],
                                ),
                              ),
                      ),
                      if (layer.isVisible)
                        Opacity(
                          opacity: skin == ThemeSkin.custom ? 0.85 : 0.6,
                          child: layer,
                        ),
                      if (hint != null)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                color: scheme.primary,
                                size: 28,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hint!,
                                style: context.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isSelected)
                        const Positioned(top: 6, right: 6, child: SelectIcon()),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall,
                    ),
                  ),
                  for (final color in [
                    scheme.primary,
                    scheme.secondary,
                    scheme.tertiary,
                  ])
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkinOpacityItem extends ConsumerWidget {
  const _SkinOpacityItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm2 = ref.watch(
      themeSettingProvider.select(
        (state) => VM2(
          ThemeSkinLayer(
            skin: state.skin,
            imagePath: state.skinImagePath,
          ).isVisible,
          state.skinOpacity,
        ),
      ),
    );
    if (!vm2.a) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final opacity = vm2.b.clamp(minSkinOpacity, maxSkinOpacity);
    final percent = (opacity * 100).round();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListItem(
              leading: const Icon(Icons.opacity),
              horizontalTitleGap: 12,
              title: Text(
                context.appLocalizations.skinOpacity,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 32,
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderDefaultsM3(context),
                      child: Slider(
                        key: const ValueKey('theme_skin_opacity'),
                        padding: EdgeInsets.zero,
                        min: minSkinOpacity,
                        max: maxSkinOpacity,
                        value: opacity,
                        onChanged: (value) {
                          ref
                              .read(themeSettingProvider.notifier)
                              .update(
                                (state) => state.copyWith(skinOpacity: value),
                              );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '$percent%',
                      style: context.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextScaleFactorItem extends ConsumerWidget {
  const _TextScaleFactorItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final textScale = ref.watch(
      themeSettingProvider.select((state) => state.textScale),
    );
    final String process = '${(textScale.scale * 100).round()}%';
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListItem.toggle(
              leading: const Icon(Icons.text_fields),
              horizontalTitleGap: 12,
              title: Text(
                appLocalizations.textScale,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              value: textScale.enable,
              onChanged: (value) {
                ref
                    .read(themeSettingProvider.notifier)
                    .update((state) => state.copyWith.textScale(enable: value));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              spacing: 32,
              children: [
                Expanded(
                  child: DisabledMask(
                    status: !textScale.enable,
                    child: ActivateBox(
                      active: textScale.enable,
                      child: SliderTheme(
                        data: SliderDefaultsM3(context),
                        child: Slider(
                          padding: EdgeInsets.zero,
                          min: minTextScale,
                          max: maxTextScale,
                          value: textScale.scale,
                          onChanged: (value) {
                            ref
                                .read(themeSettingProvider.notifier)
                                .update(
                                  (state) =>
                                      state.copyWith.textScale(scale: value),
                                );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(process, style: context.textTheme.titleMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
