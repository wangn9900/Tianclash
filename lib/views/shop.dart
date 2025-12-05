import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/v2board_service.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/v2board.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/order_confirm.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShopView extends ConsumerStatefulWidget {
  const ShopView({super.key});

  @override
  ConsumerState<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends ConsumerState<ShopView> {
  bool _loading = false;
  List<Plan> _plans = [];
  final _v2boardService = V2BoardService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPlans();
    });
  }

  Future<void> _loadPlans() async {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null || currentProfile.jwt == null) return;

    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse(currentProfile.url);
      final baseUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      final plansData = await _v2boardService.fetchPlans(baseUrl, currentProfile.jwt!);
      
      if (plansData != null) {
        setState(() {
          _plans = plansData.map((e) => Plan.fromJson(e)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        context.showNotifier('Failed to load plans: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _isJsonContent(String content) {
    try {
      final parsed = json.decode(content);
      return parsed is List && parsed.isNotEmpty && parsed[0] is Map && parsed[0].containsKey('feature');
    } catch (e) {
      return false;
    }
  }

  List<dynamic> _parseJsonContent(String content) {
    try {
      return json.decode(content);
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentProfile = ref.watch(currentProfileProvider);

    if (currentProfile == null || currentProfile.jwt == null) {
      return CommonScaffold(
        title: appLocalizations.shop,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '请通过网页访问商店购买套餐',
                style: context.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (currentProfile != null)
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      final uri = Uri.parse(currentProfile.url);
                      final shopUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/#/plan';
                      await launchUrl(Uri.parse(shopUrl), mode: LaunchMode.externalApplication);
                    } catch (e) {
                      if (mounted) {
                        context.showNotifier('无法打开商店页面');
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开网页商店'),
                ),
            ],
          ),
        ),
      );
    }

    return CommonScaffold(
      title: appLocalizations.shop,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPlans,
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _plans.length,
                itemBuilder: (context, index) {
                  final plan = _plans[index];
                  return _buildPlanCard(plan);
                },
              ),
            ),
    );
  }

  Widget _buildPlanCard(Plan plan) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildPlanContent(plan.content),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderConfirmPage(plan: plan),
                    ),
                  );
                },
                child: const Text('订阅套餐'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanContent(String content) {
    if (_isJsonContent(content)) {
      final features = _parseJsonContent(content);
      return ListView.builder(
        itemCount: features.length,
        itemBuilder: (context, index) {
          final feature = features[index];
          final isSupported = feature['support'] == true;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  isSupported ? Icons.check_circle : Icons.cancel,
                  color: isSupported ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    feature['feature'] ?? '',
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: isSupported ? null : context.colorScheme.onSurface.withOpacity(0.5),
                      decoration: isSupported ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      // Fallback for HTML content (simplified)
      return SingleChildScrollView(
        child: Text(content.replaceAll(RegExp(r'<[^>]*>'), '')), // Strip HTML tags
      );
    }
  }
}
