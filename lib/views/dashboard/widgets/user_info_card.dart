import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/v2board_service.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/v2board.dart';
import 'package:fl_clash/enum/enum.dart' as app_enum;
import 'package:fl_clash/enum/enum.dart'; // Add direct import for PageLabel if not using prefix
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/order_confirm.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class UserInfoCard extends ConsumerStatefulWidget {
  const UserInfoCard({super.key});

  @override
  ConsumerState<UserInfoCard> createState() => _UserInfoCardState();
}

class _UserInfoCardState extends ConsumerState<UserInfoCard> {
  final _v2boardService = V2BoardService();
  UserInfo? _userInfo;
  List<Plan> _plans = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserInfo();
    });
  }

  Future<void> _loadUserInfo() async {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null || currentProfile.jwt == null) return;

    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final uri = Uri.parse(currentProfile.url);
      final baseUrl =
          '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

      // 并行请求以加快速度
      final results = await Future.wait([
        _v2boardService.getUserInfo(baseUrl, currentProfile.jwt!),
        _v2boardService.fetchPlans(baseUrl, currentProfile.jwt!),
      ]);

      final userInfoMap = results[0] as Map<String, dynamic>?;
      final plansMap = results[1] as List<dynamic>?;

      if (mounted && userInfoMap != null) {
        setState(() {
          _userInfo = UserInfo.fromJson(userInfoMap);
          if (plansMap != null) {
            _plans = plansMap.map((e) => Plan.fromJson(e)).toList();
          }
        });
      }

      // 静默更新 Profile，不触发全局 Loading
      globalState.appController.applyProfile(silence: true);
    } catch (e) {
      debugPrint('Failed to load user info: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null || timestamp <= 0) return '永久有效';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _getPlanName(int? planId) {
    if (planId == null) return 'Free Plan';
    final plan = _plans.firstWhere(
      (p) => p.id == planId,
      orElse: () => Plan(id: -1, name: 'Plan: $planId', content: ''),
    );
    return plan.name;
  }

  @override
  Widget build(BuildContext context) {
    final currentProfile = ref.watch(currentProfileProvider);
    final subscriptionInfo = currentProfile?.subscriptionInfo;

    // 优先使用 API 获取的数据，降级使用 SubscriptionInfo
    final apiTotal = _userInfo?.transferEnable ?? 0;
    final subTotal = subscriptionInfo?.total ?? 0;
    final total = apiTotal > 0 ? apiTotal : subTotal;

    final apiUsed = _userInfo?.transferUsed ?? 0;
    final subUsed =
        (subscriptionInfo?.upload ?? 0) + (subscriptionInfo?.download ?? 0);
    final used = apiUsed > subUsed ? apiUsed : subUsed;

    final progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final expiredAt = _userInfo?.expiredAt ?? subscriptionInfo?.expire;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF90CAF9), // 明显的蓝色 (Blue 200)
            Color(0xFFE3F2FD), // 淡蓝
            Colors.white, // 纯白
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64B5F6).withOpacity(0.25), // 更明显的阴影
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            globalState.appController.toPage(app_enum.PageLabel.user);
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Avatar, Info, Expiry
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: context.colorScheme.primaryContainer,
                      backgroundImage: _userInfo?.avatarUrl != null
                          ? NetworkImage(_userInfo!.avatarUrl!)
                          : null,
                      child: _userInfo?.avatarUrl == null
                          ? Icon(
                              Icons.person,
                              color: context.colorScheme.primary,
                              size: 20,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userInfo?.email ??
                                currentProfile?.label ??
                                'Guest',
                            style: context.textTheme.titleMedium?.toSoftBold,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colorScheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getPlanName(_userInfo?.planId),
                              style: context.textTheme.labelSmall?.copyWith(
                                color: context.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '到期时间',
                            style: context.textTheme.labelSmall?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            _formatDate(expiredAt),
                            style: context.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Row 2: Traffic Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (_loading)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colorScheme.primary,
                            ),
                          )
                        else
                          Icon(
                            Icons.donut_large,
                            size: 14,
                            color: context.colorScheme.primary,
                          ),
                        const SizedBox(width: 6),
                        Text('已用流量', style: context.textTheme.bodySmall),
                      ],
                    ),
                    Text(
                      '${_formatBytes(used)} / ${_formatBytes(total)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Row 3: Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        context.colorScheme.surfaceContainerHighest,
                    color: context.colorScheme.primary,
                  ),
                ),

                const SizedBox(height: 12),

                // Row 4: Renew Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final planId = _userInfo?.planId;
                      if (planId != null && planId > 0) {
                        // 如果有当前套餐,直接跳转到续费确认页面
                        final currentPlan = _plans.firstWhere(
                          (p) => p.id == planId,
                          orElse: () => Plan(
                            id: planId,
                            name: _getPlanName(planId),
                            content: '',
                          ),
                        );

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderConfirmPage(plan: currentPlan),
                          ),
                        );
                      } else {
                        // 如果没有套餐,跳转到套餐选择页面
                        globalState.appController.toPage(
                          app_enum.PageLabel.shop,
                        );
                      }
                    },
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: const Text('续费套餐'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colorScheme.primaryContainer,
                      foregroundColor: context.colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
