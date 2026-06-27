import 'package:flutter/material.dart';

import '../../effects/app_sound_effects.dart';

class AppSideBarItem {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;
  final bool enabled;

  const AppSideBarItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = Colors.white70,
    this.enabled = true,
  });
}

/// ロビー・対戦・ランキングで共通の右サイドバー
class AppSideBar extends StatelessWidget {
  final bool hideOpponentNames;
  final VoidCallback? onToggleHideOpponentNames;
  final List<AppSideBarItem> items;

  const AppSideBar({
    super.key,
    this.hideOpponentNames = false,
    this.onToggleHideOpponentNames,
    this.items = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      decoration: const BoxDecoration(
        color: Colors.black38,
        border: Border(left: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          if (onToggleHideOpponentNames != null) ...[
            _SideTabButton(
              label: hideOpponentNames ? '名前非表示' : '名前表示',
              icon: hideOpponentNames ? Icons.visibility_off : Icons.visibility,
              accent: hideOpponentNames ? Colors.amberAccent : Colors.white70,
              onTap: () => withButtonSound(onToggleHideOpponentNames!),
            ),
            if (items.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Divider(height: 1, color: Colors.white24),
              ),
          ],
          for (var i = 0; i < items.length; i++) ...[
            _SideTabButton(
              label: items[i].label,
              icon: items[i].icon,
              accent: items[i].enabled ? items[i].accent : Colors.white24,
              onTap: items[i].enabled ? items[i].onTap : null,
            ),
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Divider(height: 1, color: Colors.white24),
              ),
          ],
        ],
      ),
    );
  }
}

class _SideTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;

  const _SideTabButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null ? null : () => withButtonSound(onTap!),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
