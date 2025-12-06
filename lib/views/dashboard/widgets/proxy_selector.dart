import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fl_clash/enum/enum.dart';
import 'package:collection/collection.dart';

class ProxySelector extends ConsumerStatefulWidget {
  const ProxySelector({super.key});

  @override
  ConsumerState<ProxySelector> createState() => _ProxySelectorState();
}

class _ProxySelectorState extends ConsumerState<ProxySelector> {
  Group _getMainGroup(List<Group> groups, Mode mode) {
    if (mode == Mode.global) {
      final globalGroup = groups.firstWhereOrNull((g) => g.name == 'GLOBAL');
      if (globalGroup != null) return globalGroup;
    }

    return groups.firstWhereOrNull(
          (g) =>
              g.type == GroupType.Selector &&
              ['Proxy', '节点选择', '代理'].contains(g.name),
        ) ??
        groups.firstWhereOrNull((g) => g.type == GroupType.Selector) ??
        groups.first;
  }

  Future<void> _showProxySelector(BuildContext context) async {
    final groups = ref.read(currentGroupsStateProvider).value;
    if (groups.isEmpty) return;

    final mode = ref.read(patchClashConfigProvider).mode;
    final mainGroup = _getMainGroup(groups, mode);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return _ProxyListSheet(
              group: mainGroup,
              scrollController: scrollController,
              onProxySelected: (proxy) {
                globalState.appController.changeProxy(
                  groupName: mainGroup.name,
                  proxyName: proxy.name,
                );
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print('ProxySelector: build called');
    final groups = ref.watch(currentGroupsStateProvider).value ?? [];
    final selectedMap = ref.watch(selectedMapProvider);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final currentProfile = ref.watch(currentProfileProvider);

    if (groups.isEmpty) {
      String message = '未找到节点';
      Color iconColor = Colors.orange;
      IconData icon = Icons.error_outline;

      if (currentProfile == null) {
        message = '请订阅套餐';
        iconColor = Colors.blue;
        icon = Icons.shopping_cart_outlined;
      } else {
        final info = currentProfile.subscriptionInfo;
        if (info != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (info.expire > 0 && info.expire < now) {
            message = '套餐过期请续费';
            iconColor = Colors.red;
            icon = Icons.timer_off_outlined;
          } else if (info.total > 0 &&
              (info.upload + info.download) >= info.total) {
            message = '流量用尽请续费';
            iconColor = Colors.red;
            icon = Icons.data_usage;
          } else {
            // Profile exists, info exists, but no nodes found.
            // This could happen if the subscription returns an empty list but is valid.
            message = '订阅内容为空';
          }
        } else {
          // Profile exists but no info.
          message = '无法获取订阅信息';
        }
      }

      return CommonCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: context.textTheme.bodyMedium),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  print('ProxySelector: Refresh clicked, calling applyProfile');
                  globalState.appController.applyProfile();
                },
                tooltip: '重试',
              ),
            ],
          ),
        ),
      );
    }

    final mainGroup = _getMainGroup(groups, mode);

    print('ProxySelector: groups count: ${groups.length}, mode: $mode');
    print('ProxySelector: mainGroup: ${mainGroup.name}');

    // 优先使用 selectedMap,如果没有则使用 mainGroup.now
    final currentProxyName = selectedMap[mainGroup.name] ?? mainGroup.now;

    final currentProxy = mainGroup.all.firstWhere(
      (p) => p.name == currentProxyName,
      orElse: () => Proxy(name: currentProxyName ?? '自动选择', type: ''),
    );

    // 获取当前节点的延迟
    final delay = currentProxyName != null
        ? ref.watch(
            getDelayProvider(
              proxyName: currentProxyName,
              testUrl: mainGroup.testUrl,
            ),
          )
        : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0F7FF), // 极淡的蓝色背景
            Colors.white,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE3F2FD).withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showProxySelector(context),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.public,
                  color: context.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '节点选择${mainGroup.name == 'GLOBAL' ? ' (全局)' : ''}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentProxy.name,
                        style: context.textTheme.titleMedium?.toSoftBold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (delay != null && delay > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getDelayColor(delay).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${delay}ms',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: _getDelayColor(delay),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.expand_more,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getDelayColor(int delay) {
    if (delay <= 400) return Colors.green;
    if (delay <= 1800) return Colors.orange;
    return Colors.red;
  }
}

class _ProxyListSheet extends ConsumerStatefulWidget {
  final Group group;
  final ScrollController scrollController;
  final Function(Proxy) onProxySelected;

  const _ProxyListSheet({
    required this.group,
    required this.scrollController,
    required this.onProxySelected,
  });

  @override
  ConsumerState<_ProxyListSheet> createState() => _ProxyListSheetState();
}

class _ProxyListSheetState extends ConsumerState<_ProxyListSheet> {
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    // 自动开始延迟测试
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDelayTest();
    });
  }

  Future<void> _startDelayTest() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
    });

    try {
      await delayTest(widget.group.all, widget.group.testUrl);
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMap = ref.watch(selectedMapProvider);
    final currentProxyName = selectedMap[widget.group.name];

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 顶部拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colorScheme.onSurfaceVariant.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择节点',
                        style: context.textTheme.titleLarge?.toSoftBold,
                      ),
                      if (widget.group.all.isNotEmpty)
                        Text(
                          '共 ${widget.group.all.length} 个节点',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isTesting ? null : _startDelayTest,
                  icon: _isTesting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colorScheme.primary,
                          ),
                        )
                      : Icon(Icons.speed, color: context.colorScheme.primary),
                  tooltip: '测试延迟',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 节点列表
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.group.all.length,
              itemBuilder: (context, index) {
                final proxy = widget.group.all[index];
                final isSelected = proxy.name == currentProxyName;
                final delay = ref.watch(
                  getDelayProvider(
                    proxyName: proxy.name,
                    testUrl: widget.group.testUrl,
                  ),
                );

                return _ProxyListItem(
                  proxy: proxy,
                  isSelected: isSelected,
                  delay: delay,
                  onTap: () => widget.onProxySelected(proxy),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyListItem extends StatelessWidget {
  final Proxy proxy;
  final bool isSelected;
  final int? delay;
  final VoidCallback onTap;

  const _ProxyListItem({
    required this.proxy,
    required this.isSelected,
    required this.delay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            // 选中指示器
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Colors.green
                      : context.colorScheme.outline,
                  width: 2,
                ),
                color: isSelected ? Colors.green : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // 节点名称
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proxy.name,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (proxy.type.isNotEmpty)
                    Text(
                      proxy.type,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // 延迟显示
            if (delay != null)
              if (delay! == 0)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (delay! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getDelayColor(
                      delay!,
                      context,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${delay}ms',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: _getDelayColor(delay!, context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: context.colorScheme.error,
                ),
          ],
        ),
      ),
    );
  }

  Color _getDelayColor(int delay, BuildContext context) {
    if (delay <= 400) return Colors.green;
    if (delay <= 1800) return Colors.orange;
    return Colors.red;
  }
}
