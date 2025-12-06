import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';

class ModeSwitcher extends ConsumerWidget {
  const ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final tunEnabled = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.enable),
    );
    print('ModeSwitcher: build called, tunEnabled=$tunEnabled');

    return CommonCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SegmentedButton<Mode>(
                segments: [
                  ButtonSegment<Mode>(
                    value: Mode.rule,
                    label: const Text('智能'),
                    icon: const Icon(Icons.playlist_add_check),
                  ),
                  ButtonSegment<Mode>(
                    value: Mode.global,
                    label: const Text('全局'),
                    icon: const Icon(Icons.public),
                  ),
                ],
                selected: {mode == Mode.direct ? Mode.rule : mode},
                onSelectionChanged: (Set<Mode> newSelection) {
                  if (newSelection.isEmpty) return;
                  final selectedMode = newSelection.first;
                  globalState.appController.changeMode(selectedMode);
                },
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            if (system.isDesktop) ...[
              const SizedBox(width: 12),
              const Text(
                "开启虚拟网卡",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: tunEnabled,
                  onChanged: (value) {
                    print('ModeSwitcher: TUN switch changed to $value');
                    // 更新 TUN 配置
                    ref
                        .read(patchClashConfigProvider.notifier)
                        .updateState(
                          (state) => state.copyWith.tun(enable: value),
                        );

                    // 使用 Future.microtask 确保状态更新后再执行
                    Future.microtask(() async {
                      if (value) {
                        // 打开 TUN → 自动连接
                        print('ModeSwitcher: TUN enabled, auto-starting...');
                        await globalState.appController.startSystemProxy();
                      } else {
                        // 关闭 TUN → 自动断开
                        print('ModeSwitcher: TUN disabled, auto-stopping...');
                        await globalState.appController.stopSystemProxy();
                      }
                    });
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
