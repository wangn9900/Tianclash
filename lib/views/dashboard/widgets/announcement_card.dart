import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/v2board_service.dart';
import 'package:fl_clash/models/v2board.dart';
import 'package:fl_clash/providers/providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

class AnnouncementCard extends ConsumerStatefulWidget {
  const AnnouncementCard({super.key});

  @override
  ConsumerState<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<AnnouncementCard> {
  final _v2boardService = V2BoardService();
  List<Notice> _notices = [];
  bool _isLoading = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotices();
    });
  }

  Future<void> _loadNotices() async {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null || currentProfile.jwt == null) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final uri = Uri.parse(currentProfile.url);
      final baseUrl =
          '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

      final result = await _v2boardService.fetchNotices(
        baseUrl,
        currentProfile.jwt!,
        pageSize: 10,
      );

      if (result != null && result['data'] != null) {
        final noticeList = (result['data'] as List)
            .map((e) => Notice.fromJson(e as Map<String, dynamic>))
            .toList();

        if (mounted) {
          setState(() {
            _notices = noticeList;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading notices: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy/MM/dd').format(date);
  }

  String _stripHtmlTags(String htmlString) {
    // 替换常见的HTML标签为换行或空格
    var text = htmlString
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p>'), '\n')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<div>'), '\n')
        .replaceAll(RegExp(r'</div>'), '\n')
        .replaceAll(RegExp(r'<h[1-6]>'), '\n')
        .replaceAll(RegExp(r'</h[1-6]>'), '\n')
        .replaceAll(RegExp(r'<li>'), '\n• ')
        .replaceAll(RegExp(r'</li>'), '')
        .replaceAll(RegExp(r'<[^>]*>'), '') // 移除所有其他HTML标签
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n\n') // 合并多个空行
        .trim();

    return text;
  }

  void _showNoticeDetail(Notice notice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notice.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (notice.createdAt > 0)
                Text(
                  _formatDate(notice.createdAt),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 12),
              Html(
                data: notice.content,
                style: {
                  "body": Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(14),
                  ),
                  "p": Style(margin: Margins.only(bottom: 8)),
                  "h1": Style(
                    fontSize: FontSize(20),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 8, bottom: 8),
                  ),
                  "h2": Style(
                    fontSize: FontSize(18),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 8, bottom: 8),
                  ),
                  "h3": Style(
                    fontSize: FontSize(16),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 8, bottom: 8),
                  ),
                  "h4": Style(
                    fontSize: FontSize(15),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 6, bottom: 6),
                  ),
                  "h5": Style(
                    fontSize: FontSize(14),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 6, bottom: 6),
                  ),
                  "a": Style(textDecoration: TextDecoration.underline),
                  "ul": Style(margin: Margins.only(left: 16, bottom: 8)),
                  "ol": Style(margin: Margins.only(left: 16, bottom: 8)),
                },
                onLinkTap: (url, attributes, element) async {
                  if (url != null) {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appLocalizations.cancel),
          ),
        ],
      ),
    );
  }

  void _nextNotice() {
    if (_notices.isNotEmpty) {
      setState(() {
        _currentIndex = (_currentIndex + 1) % _notices.length;
      });
    }
  }

  void _previousNotice() {
    if (_notices.isNotEmpty) {
      setState(() {
        _currentIndex = (_currentIndex - 1 + _notices.length) % _notices.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Icon(Icons.campaign, color: context.colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '网站公告',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_notices.isEmpty)
                    Text(
                      '暂无公告',
                      style: context.textTheme.titleMedium?.toSoftBold,
                    )
                  else
                    InkWell(
                      onTap: () => _showNoticeDetail(_notices[_currentIndex]),
                      child: Text(
                        _notices[_currentIndex].title,
                        style: context.textTheme.titleMedium?.toSoftBold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (_notices.length > 1) ...[
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _previousNotice,
                tooltip: '上一条',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Text(
                '${_currentIndex + 1}/${_notices.length}',
                style: context.textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _nextNotice,
                tooltip: '下一条',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ] else if (_notices.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: () => _showNoticeDetail(_notices[_currentIndex]),
                tooltip: '查看详情',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}
