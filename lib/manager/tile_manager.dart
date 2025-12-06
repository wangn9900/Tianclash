import 'package:fl_clash/models/app.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class TileManager extends StatefulWidget {
  final Widget child;

  const TileManager({super.key, required this.child});

  @override
  State<TileManager> createState() => _TileContainerState();
}

class _TileContainerState extends State<TileManager> with TileListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  Future<void> onStart() async {
    if (globalState.appState.isStart) {
      return;
    }
    globalState.appController.updateStatus(true);
    super.onStart();
  }

  @override
  Future<void> onStop() async {
    // Kotlin 侧已经停止了 VPN 服务，这里只需要同步本地 UI 状态
    // 调用 syncDisconnectState 确保所有 Providers 和全局状态正确重置
    print(
      'TileManager: onStop received from Kotlin, syncing disconnect state...',
    );
    await globalState.appController.syncDisconnectState();
    super.onStop();
  }

  @override
  void initState() {
    super.initState();
    tile?.addListener(this);
  }

  @override
  void dispose() {
    tile?.removeListener(this);
    super.dispose();
  }
}
