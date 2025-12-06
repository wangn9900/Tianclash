import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkDetection extends ConsumerStatefulWidget {
  const NetworkDetection({super.key});

  @override
  ConsumerState<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends ConsumerState<NetworkDetection> {
  String _countryCodeToEmoji(String countryCode) {
    final String code = countryCode.toUpperCase();
    if (code.length != 2) {
      return countryCode;
    }
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  String _maskIp(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.***.***.${parts[3]}';
    }
    return ip;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkDetectionState>(
      valueListenable: detectionState.state,
      builder: (_, state, _) {
        final ipInfo = state.ipInfo;
        final isLoading = state.isLoading;

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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.network_check,
                  color: context.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocalizations.networkDetection,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (ipInfo != null)
                        Text(
                          '${_countryCodeToEmoji(ipInfo.countryCode)} ${_maskIp(ipInfo.ip)}',
                          style: context.textTheme.titleMedium?.toSoftBold,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          '检测失败',
                          style: context.textTheme.titleMedium?.toSoftBold,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    detectionState.startCheck();
                  },
                  tooltip: '刷新',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
