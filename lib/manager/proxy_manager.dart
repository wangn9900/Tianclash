import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxyManager extends ConsumerStatefulWidget {
  final Widget child;

  const ProxyManager({super.key, required this.child});

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _updateProxy(ProxyState proxyState) async {
    final isStart = proxyState.isStart;
    final systemProxy = proxyState.systemProxy;
    final port = proxyState.port;
    commonPrint.log(
      'ProxyManager: _updateProxy called. isStart: $isStart, systemProxy: $systemProxy, port: $port',
    );

    if (isStart && systemProxy) {
      commonPrint.log('ProxyManager: >>> Invoking native startProxy');
      final res = await proxy?.startProxy(port, proxyState.bassDomain);
      commonPrint.log('ProxyManager: <<< Native startProxy result: $res');
    } else {
      commonPrint.log('ProxyManager: >>> Invoking native stopProxy');
      final res = await proxy?.stopProxy();
      commonPrint.log('ProxyManager: <<< Native stopProxy result: $res');
    }
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(proxyStateProvider, (prev, next) {
      if (prev != next) {
        _updateProxy(next);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
