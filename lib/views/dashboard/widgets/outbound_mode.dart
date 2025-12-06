import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OutboundMode extends StatelessWidget {
  const OutboundMode({super.key});

  Color _getTextColor(BuildContext context, Mode mode) {
    return switch (mode) {
      Mode.rule => context.colorScheme.onSecondaryContainer,
      Mode.global => context.colorScheme.onPrimaryContainer,
      Mode.direct => context.colorScheme.onTertiaryContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (_, ref, _) {
        final mode = ref.watch(
          patchClashConfigProvider.select((state) => state.mode),
        );

        return Row(
          children: [
            Expanded(
              child: SegmentedButton<Mode>(
                segments: const [
                  ButtonSegment<Mode>(
                    value: Mode.rule,
                    label: Text('智能'),
                    icon: Icon(Icons.auto_fix_high),
                  ),
                  ButtonSegment<Mode>(
                    value: Mode.global,
                    label: Text('全局'),
                    icon: Icon(Icons.public),
                  ),
                ],
                selected: {mode == Mode.direct ? Mode.rule : mode},
                onSelectionChanged: (Set<Mode> newSelection) {
                  globalState.appController.changeMode(newSelection.first);
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.comfortable,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            if (system.isDesktop) ...[
              const SizedBox(width: 16),
              const Text(
                "开启虚拟网卡",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: ref.watch(
                    patchClashConfigProvider.select(
                      (state) => state.tun.enable,
                    ),
                  ),
                  onChanged: (value) {
                    print('OutboundMode: TUN switch changed to $value');
                    // 更新 TUN 配置
                    ref
                        .read(patchClashConfigProvider.notifier)
                        .updateState(
                          (state) => state.copyWith.tun(enable: value),
                        );

                    // 使用 Future.microtask 确保状态更新后再执行
                    Future.microtask(() async {
                      if (value) {
                        // 打开 TUN → 先更新配置，再自动连接
                        print(
                          'OutboundMode: TUN enabled, updating config and starting...',
                        );
                        // 先更新配置让核心知道要开启 TUN
                        await globalState.appController.updateClashConfig();
                        // 再启动连接
                        await globalState.appController.startSystemProxy();
                      } else {
                        // 关闭 TUN → 自动断开
                        print('OutboundMode: TUN disabled, auto-stopping...');
                        await globalState.appController.stopSystemProxy();
                      }
                    });
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
