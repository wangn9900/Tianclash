import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:fl_clash/common/archive.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_clash/pages/pages.dart';

import 'common/common.dart';
import 'models/models.dart';

class AppController {
  int? lastProfileModified;

  final BuildContext context;
  final WidgetRef _ref;

  AppController(this.context, WidgetRef ref) : _ref = ref;

  void setupClashConfigDebounce() {
    debouncer.call(FunctionTag.setupClashConfig, () async {
      await setupClashConfig();
    });
  }

  Future<void> updateClashConfigDebounce() async {
    debouncer.call(FunctionTag.updateClashConfig, () async {
      await updateClashConfig();
    });
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void addCheckIpNumDebounce() {
    debouncer.call(FunctionTag.addCheckIpNum, () {
      _ref.read(checkIpNumProvider.notifier).add();
    });
  }

  void applyProfileDebounce({bool silence = false}) {
    debouncer.call(FunctionTag.applyProfile, (silence) {
      applyProfile(silence: silence);
    }, args: [silence]);
  }

  void savePreferencesDebounce() {
    debouncer.call(FunctionTag.savePreferences, savePreferences);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(groupName: groupName, proxyName: proxyName);
      await updateGroups();
    }, args: [groupName, proxyName]);
  }

  Future<void> restartCore() async {
    globalState.isUserDisconnected = true;
    await coreController.shutdown();
    await _connectCore();
    await _initCore();
    _ref.read(initProvider.notifier).value = true;
    if (_ref.read(isStartProvider)) {
      await globalState.handleStart();
    }
  }

  Future<void> tryStartCore() async {
    if (coreController.isCompleted) {
      return;
    }
    globalState.isUserDisconnected = true;
    await _connectCore();
    await _initCore();
    _ref.read(initProvider.notifier).value = true;
    if (_ref.read(isStartProvider)) {
      await globalState.handleStart();
    }
  }

  Future<void> updateStatus(bool isStart) async {
    if (isStart) {
      _ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;

      bool startSuccess = false;
      try {
        await globalState.appController.tryStartCore();

        // Double check: If we are connected, we should be able to get groups
        // Wait briefly for core to stabilize
        if (system.isAndroid)
          await Future.delayed(const Duration(milliseconds: 500));

        // Verify core is responding
        try {
          final groups = await coreController
              .getProxiesGroups(
                sortType: ProxiesSortType.none,
                delayMap: {},
                selectedMap: {},
                defaultTestUrl: _ref.read(appSettingProvider).testUrl,
              )
              .timeout(const Duration(seconds: 2));

          if (groups.isNotEmpty) {
            startSuccess = true;
          } else {
            print(
              'AppController: Core started but returned no groups. Treating as failure.',
            );
            startSuccess = false;
          }
        } catch (e) {
          print('AppController: Core verification failed after start: $e');
          startSuccess = false;
        }
      } catch (e) {
        print('AppController: tryStartCore failed: $e');
        startSuccess = false;
      }

      if (startSuccess) {
        _ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
        await globalState.handleStart([updateRunTime, updateTraffic]);
        if (system.isAndroid) {
          await Future.delayed(const Duration(milliseconds: 1500));
          coreController.closeConnections();
          await Future.delayed(const Duration(milliseconds: 200));
          final groups = getCurrentGroups();
          for (final group in groups) {
            if (group.type == GroupType.Selector && group.now != null) {
              await changeProxy(groupName: group.name, proxyName: group.now!);
            }
          }
        }
        final currentLastModified = await _ref
            .read(currentProfileProvider)
            ?.profileLastModified;
        if (currentLastModified == null) {
          addCheckIpNumDebounce();
          return;
        }
        if (lastProfileModified != null &&
            currentLastModified <= lastProfileModified!) {
          addCheckIpNumDebounce();
          return;
        }
        applyProfileDebounce();
        _ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      } else {
        // Revert to disconnected if start failed
        print(
          'AppController: Start failed or validation failed. Reverting to Disconnected.',
        );
        if (globalState.isStart) {
          await globalState.handleStop();
        }
        coreController.resetTraffic();
        _ref.read(trafficsProvider.notifier).clear();
        _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('连接失败，请检查网络或节点配置')));
        }
      }
    } else {
      // Android 使用可靠的原生停止方法,复用状态栏逻辑
      if (system.isAndroid) {
        print('AppController: Using forceStopVpn for reliable stop on Android');
        try {
          await app?.forceStopVpn();
          // 等待服务完全停止
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print(
            'AppController: forceStopVpn failed: $e, fallback to service.stop()',
          );
          await globalState.handleStop();
        }
      } else {
        // Windows/macOS/Linux:
        // 1. 关闭 TUN 虚拟网卡
        // 2. 关闭系统代理
        // 3. 更新配置让核心应用
        print('AppController: Stopping on desktop...');

        // 先禁用 TUN
        final currentTunEnabled = _ref.read(
          patchClashConfigProvider.select((state) => state.tun.enable),
        );
        if (currentTunEnabled) {
          print('AppController: Disabling TUN...');
          _ref
              .read(patchClashConfigProvider.notifier)
              .updateState((state) => state.copyWith.tun(enable: false));
          // 立即发送配置更新到核心
          try {
            final updateParams = _ref.read(updateParamsProvider);
            await coreController.updateConfig(
              updateParams.copyWith.tun(enable: false),
            );
            print('AppController: TUN disabled');
          } catch (e) {
            print('AppController: Failed to disable TUN: $e');
          }
        }

        // 关闭系统代理
        try {
          await proxy?.stopProxy();
          print('AppController: System proxy stopped');
        } catch (e) {
          print('AppController: stopProxy error: $e');
        }

        // 关闭所有活动连接
        print('AppController: Closing all connections...');
        coreController.closeConnections();

        await globalState.handleStop();
      }

      coreController.resetTraffic();
      _ref.read(trafficsProvider.notifier).clear();
      _ref.read(totalTrafficProvider.notifier).value = Traffic();
      _ref.read(runTimeProvider.notifier).value = null;

      // 等待代理完全停止后再刷新 IP
      await Future.delayed(const Duration(milliseconds: 800));
      addCheckIpNumDebounce();
      _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    }
  }

  void updateRunTime() {
    final startTime = globalState.startTime;
    if (startTime != null) {
      final startTimeStamp = startTime.millisecondsSinceEpoch;
      final nowTimeStamp = DateTime.now().millisecondsSinceEpoch;
      _ref.read(runTimeProvider.notifier).value = nowTimeStamp - startTimeStamp;
    } else {
      _ref.read(runTimeProvider.notifier).value = null;
    }
  }

  Future<void> updateTraffic() async {
    final onlyStatisticsProxy = _ref.read(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    final traffic = await coreController.getTraffic(onlyStatisticsProxy);
    _ref.read(trafficsProvider.notifier).addTraffic(traffic);
    _ref.read(totalTrafficProvider.notifier).value = await coreController
        .getTotalTraffic(onlyStatisticsProxy);
  }

  Future<void> addProfile(Profile profile) async {
    _ref.read(profilesProvider.notifier).setProfile(profile);

    // Sync globalState.config with the latest profiles
    final currentProfiles = _ref.read(profilesProvider);
    globalState.config = globalState.config.copyWith(profiles: currentProfiles);

    await savePreferences();
    if (_ref.read(currentProfileIdProvider) != null) return;
    await tryStartCore();
    _ref.read(currentProfileIdProvider.notifier).value = profile.id;

    // Sync globalState.config with the latest currentProfileId
    globalState.config = globalState.config.copyWith(
      currentProfileId: profile.id,
    );

    await savePreferences();

    // 强制更新配置，确保新账号的订阅能正确下发
    print(
      'AppController: addProfile - Syncing config and updating Clash config...',
    );
    await updateClashConfig();
  }

  Future<void> deleteProfile(String id) async {
    _ref.read(profilesProvider.notifier).deleteProfileById(id);
    clearEffect(id);
    if (globalState.config.currentProfileId == id) {
      final profiles = globalState.config.profiles;
      final currentProfileId = _ref.read(currentProfileIdProvider.notifier);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        currentProfileId.value = updateId;
      } else {
        currentProfileId.value = null;
        updateStatus(false);
      }
    }
    await savePreferences();
  }

  Future<void> updateProviders() async {
    _ref.read(providersProvider.notifier).value = await coreController
        .getExternalProviders();
  }

  Future<void> updateLocalIp() async {
    _ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    _ref.read(localIpProvider.notifier).value = await utils.getLocalIpAddress();
  }

  Future<void> updateProfile(Profile profile) async {
    final newProfile = await profile.update();
    _ref
        .read(profilesProvider.notifier)
        .setProfile(newProfile.copyWith(isUpdating: false));
    if (profile.id == _ref.read(currentProfileIdProvider)) {
      applyProfileDebounce(silence: true);
    }
    savePreferencesDebounce();
  }

  void setProfile(Profile profile) {
    _ref.read(profilesProvider.notifier).setProfile(profile);
  }

  void setProfileAndAutoApply(Profile profile) {
    _ref.read(profilesProvider.notifier).setProfile(profile);
    if (profile.id == _ref.read(currentProfileIdProvider)) {
      applyProfileDebounce(silence: true);
    }
  }

  void setProfiles(List<Profile> profiles) {
    _ref.read(profilesProvider.notifier).value = profiles;
  }

  void addLog(Log log) {
    _ref.read(logsProvider).add(log);
  }

  void updateOrAddHotKeyAction(HotKeyAction hotKeyAction) {
    final hotKeyActions = _ref.read(hotKeyActionsProvider);
    final index = hotKeyActions.indexWhere(
      (item) => item.action == hotKeyAction.action,
    );
    if (index == -1) {
      _ref.read(hotKeyActionsProvider.notifier).value = List.from(hotKeyActions)
        ..add(hotKeyAction);
    } else {
      _ref.read(hotKeyActionsProvider.notifier).value = List.from(hotKeyActions)
        ..[index] = hotKeyAction;
    }

    _ref.read(hotKeyActionsProvider.notifier).value = index == -1
        ? (List.from(hotKeyActions)..add(hotKeyAction))
        : (List.from(hotKeyActions)..[index] = hotKeyAction);
  }

  List<Group> getCurrentGroups() {
    return _ref.read(currentGroupsStateProvider.select((state) => state.value));
  }

  String getRealTestUrl(String? url) {
    return _ref.read(getRealTestUrlProvider(url));
  }

  int getProxiesColumns() {
    return _ref.read(getProxiesColumnsProvider);
  }

  dynamic addSortNum() {
    return _ref.read(sortNumProvider.notifier).add();
  }

  String? getCurrentGroupName() {
    final currentGroupName = _ref.read(
      currentProfileProvider.select((state) => state?.currentGroupName),
    );
    return currentGroupName;
  }

  String? getSelectedProxyName(String groupName) {
    return _ref.read(getSelectedProxyNameProvider(groupName));
  }

  void updateCurrentGroupName(String groupName) {
    final profile = _ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) {
      return;
    }
    setProfile(profile.copyWith(currentGroupName: groupName));
    savePreferencesDebounce();
  }

  Future<void> updateClashConfig() async {
    await safeRun(() async {
      await _updateClashConfig();
    }, needLoading: true);
  }

  Future<void> _updateClashConfig() async {
    final updateParams = _ref.read(updateParamsProvider);
    final res = await _requestAdmin(updateParams.tun.enable);
    if (res.isError) {
      return;
    }
    final realTunEnable = _ref.read(realTunEnableProvider);
    final message = await coreController.updateConfig(
      updateParams.copyWith.tun(enable: realTunEnable),
    );
    if (message.isNotEmpty) throw message;
  }

  Future<Result<bool>> _requestAdmin(bool enableTun) async {
    // 注释：原来在 Debug 模式下直接返回 false，导致 TUN 不生效
    // 现在移除这个限制，让 Debug 模式也能使用 TUN
    print('_requestAdmin: enableTun=$enableTun, isWindows=${system.isWindows}');
    final realTunEnable = _ref.read(realTunEnableProvider);

    // 如果要开启 TUN 且当前没开启，需要请求管理员权限
    if (enableTun && !realTunEnable) {
      print('_requestAdmin: Requesting admin permission...');
      final code = await system.authorizeCore();
      print('_requestAdmin: authorizeCore result: $code');
      switch (code) {
        case AuthorizeCode.success:
          // 成功获取权限，继续更新配置
          print('_requestAdmin: Admin permission granted');
          break;
        case AuthorizeCode.none:
          // 已经有权限，继续
          print('_requestAdmin: Already has permission');
          break;
        case AuthorizeCode.error:
          // Debug 模式下忽略服务错误，允许 TUN 测试
          if (kDebugMode) {
            print(
              '_requestAdmin: Service error in debug mode, allowing TUN anyway',
            );
            break;
          }
          print('_requestAdmin: Admin permission denied');
          enableTun = false;
          break;
      }
    }

    print('_requestAdmin: Setting realTunEnable to $enableTun');
    _ref.read(realTunEnableProvider.notifier).value = enableTun;
    return Result.success(enableTun);
  }

  Future<void> setupClashConfig({bool needLoading = true}) async {
    await safeRun(() async {
      await _setupClashConfig();
    }, needLoading: needLoading);
  }

  Future<void> _setupClashConfig() async {
    await _ref.read(currentProfileProvider)?.checkAndUpdate();
    final patchConfig = _ref.read(patchClashConfigProvider);
    final res = await _requestAdmin(patchConfig.tun.enable);
    if (res.isError) {
      return;
    }
    final realTunEnable = _ref.read(realTunEnableProvider);
    final realPatchConfig = patchConfig.copyWith.tun(enable: realTunEnable);
    final message = await coreController.setupConfig(realPatchConfig);
    lastProfileModified = await _ref.read(
      currentProfileProvider.select((state) => state?.profileLastModified),
    );
    if (message.isNotEmpty) {
      throw message;
    }
  }

  Future _applyProfile({bool needLoading = true}) async {
    await setupClashConfig(needLoading: needLoading);
    await updateGroups();
    await updateProviders();
  }

  Future applyProfile({bool silence = false}) async {
    if (silence) {
      await _applyProfile(needLoading: false);
    } else {
      await safeRun(() async {
        await _applyProfile(needLoading: false);
      }, needLoading: true);
    }
    addCheckIpNumDebounce();
  }

  void handleChangeProfile() {
    _ref.read(delayDataSourceProvider.notifier).value = {};
    applyProfile();
    _ref.read(logsProvider.notifier).value = FixedList(500);
    _ref.read(requestsProvider.notifier).value = FixedList(500);
    globalState.computeHeightMapCache = {};
  }

  void updateBrightness() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref.read(systemBrightnessProvider.notifier).value =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in _ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(e.toString(), logLevel: LogLevel.warning);
      }
    }
  }

  Future<void> updateGroups() async {
    try {
      _ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
          final sortType = _ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = _ref.read(delayDataSourceProvider);
          final testUrl = _ref.read(appSettingProvider).testUrl;
          final selectedMap = _ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          return await coreController.getProxiesGroups(
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (_) {
      _ref.read(groupsProvider.notifier).value = [];
    }
  }

  Future<void> updateProfiles() async {
    for (final profile in _ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) {
        continue;
      }
      await updateProfile(profile);
    }
  }

  Future<void> savePreferences() async {
    commonPrint.log('save preferences');
    await preferences.saveConfig(globalState.config);
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    await coreController.changeProxy(
      ChangeProxyParams(groupName: groupName, proxyName: proxyName),
    );
    if (_ref.read(appSettingProvider).closeConnections) {
      coreController.closeConnections();
    }
    updateCurrentSelectedMap(groupName, proxyName);
    addCheckIpNumDebounce();
  }

  Future<void> handleBackOrExit() async {
    if (_ref.read(backBlockProvider)) {
      return;
    }
    if (_ref.read(appSettingProvider).minimizeOnExit) {
      if (system.isDesktop) {
        await savePreferences();
      }
      await system.back();
    } else {
      await handleExit();
    }
  }

  void backBlock() {
    _ref.read(backBlockProvider.notifier).value = true;
  }

  void unBackBlock() {
    _ref.read(backBlockProvider.notifier).value = false;
  }

  Future<void> handleExit() async {
    Future.delayed(commonDuration, () {
      system.exit();
    });
    try {
      await savePreferences();
      await macOS?.updateDns(true);
      await proxy?.stopProxy();
      await coreController.shutdown();
      await coreController.destroy();
    } finally {
      system.exit();
    }
  }

  Future handleClear() async {
    await preferences.clearPreferences();
    commonPrint.log('clear preferences');
    globalState.config = Config(themeProps: defaultThemeProps);
  }

  Future<void> autoCheckUpdate() async {
    if (!_ref.read(appSettingProvider).autoCheckUpdate) return;
    final res = await request.checkForUpdate();
    checkUpdateResultHandle(data: res);
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool handleError = false,
  }) async {
    if (data != null) {
      final tagName = data['tag_name'];
      final body = data['body'];
      final submits = utils.parseReleaseBody(body);
      final textTheme = context.textTheme;
      final res = await globalState.showMessage(
        title: appLocalizations.discoverNewVersion,
        message: TextSpan(
          text: '$tagName \n',
          style: textTheme.headlineSmall,
          children: [
            TextSpan(text: '\n', style: textTheme.bodyMedium),
            for (final submit in submits)
              TextSpan(text: '- $submit \n', style: textTheme.bodyMedium),
          ],
        ),
        confirmText: appLocalizations.goDownload,
      );
      if (res != true) {
        return;
      }
      launchUrl(Uri.parse('https://github.com/$repository/releases/latest'));
    } else if (handleError) {
      globalState.showMessage(
        title: appLocalizations.checkUpdate,
        message: TextSpan(text: appLocalizations.checkUpdateError),
      );
    }
  }

  Future<void> _handlePreference() async {
    if (await preferences.isInit) {
      return;
    }
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.cacheCorrupt),
    );
    if (res == true) {
      final file = File(await appPath.sharedPreferencesPath);
      final isExists = await file.exists();
      if (isExists) {
        await file.delete();
      }
    }
    await handleExit();
  }

  Future<void> _initCore() async {
    final isInit = await coreController.isInit;
    if (!isInit) {
      await coreController.init(globalState.appState.version);
    }
    await applyProfile();
  }

  Future<void> init() async {
    FlutterError.onError = (details) {
      commonPrint.log(
        'exception: ${details.exception} stack: ${details.stack}',
        logLevel: LogLevel.warning,
      );
    };
    updateTray(true);
    autoUpdateProfiles();
    autoCheckUpdate();
    autoLaunch?.updateStatus(_ref.read(appSettingProvider).autoLaunch);
    if (!_ref.read(appSettingProvider).silentLaunch) {
      window?.show();
    } else {
      window?.hide();
    }
    await _handlePreference();
    // await _handlerDisclaimer();
    // await _showCrashlyticsTip();
    await _connectCore();
    await _initCore();
    await _initStatus();
    _ref.read(initProvider.notifier).value = true;
  }

  Future<void> _connectCore() async {
    _ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    final result = await Future.wait([
      coreController.preload(),
      if (!globalState.isService) Future.delayed(Duration(milliseconds: 300)),
    ]);
    final String message = result[0];
    if (message.isNotEmpty) {
      _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      if (context.mounted) {
        context.showNotifier(message);
      }
      return;
    }
    // _ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
  }

  Future<void> _initStatus() async {
    if (system.isAndroid) {
      await globalState.updateStartTime();
    }

    // Check if VPN is actually running (system level)
    // If startTime is not null, it means the service is running
    final isServiceRunning = globalState.isStart;
    final autoRun = _ref.read(appSettingProvider).autoRun;

    // 检查是否有有效配置
    // 如果没有配置，不应该显示已连接状态
    final hasValidProfile = _ref.read(currentProfileProvider) != null;

    print(
      'AppController: _initStatus - isServiceRunning: $isServiceRunning, autoRun: $autoRun, hasValidProfile: $hasValidProfile',
    );

    // 如果没有有效配置，强制设置为断开状态
    if (!hasValidProfile) {
      print('AppController: No valid profile, forcing disconnected state...');
      if (isServiceRunning) {
        await globalState.handleStop();
      }
      _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      return;
    }

    if (isServiceRunning) {
      // CRITICAL: Verify the core is actually running, not just the service
      // Check if we can get a valid response from the core
      print('AppController: Service reports running, verifying core...');

      bool coreIsActuallyRunning = false;
      try {
        // Try to get proxies with a short timeout
        final sortType = _ref.read(
          proxiesStyleSettingProvider.select((state) => state.sortType),
        );
        final delayMap = _ref.read(delayDataSourceProvider);
        final testUrl = _ref.read(appSettingProvider).testUrl;
        final selectedMap = _ref.read(
          currentProfileProvider.select((state) => state?.selectedMap ?? {}),
        );

        final testProxies = await coreController
            .getProxiesGroups(
              selectedMap: selectedMap,
              sortType: sortType,
              delayMap: delayMap,
              defaultTestUrl: testUrl,
            )
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => throw TimeoutException('Core not responding'),
            );
        coreIsActuallyRunning = testProxies.isNotEmpty;
        print(
          'AppController: Core verification - running: $coreIsActuallyRunning',
        );
      } catch (e) {
        print('AppController: Core verification failed: $e');
        coreIsActuallyRunning = false;
      }

      if (coreIsActuallyRunning) {
        // Core is truly running, sync UI state
        print('AppController: Core is running, syncing state to connected...');
        _ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;

        // Ensure we have a current profile selected
        if (_ref.read(currentProfileIdProvider) == null &&
            _ref.read(profilesProvider).isNotEmpty) {
          final firstProfileId = _ref.read(profilesProvider).first.id;
          print(
            'AppController: No current profile, selecting first: $firstProfileId',
          );
          _ref.read(currentProfileIdProvider.notifier).value = firstProfileId;
        }

        // Update groups
        try {
          print('AppController: Updating groups with timeout...');
          await updateGroups().timeout(const Duration(seconds: 3));
        } catch (e) {
          print('AppController: Update groups timed out or failed: $e');
        }

        // If we are "connected" but have no groups, something is wrong.
        // Try to re-apply the profile.
        if (getCurrentGroups().isEmpty) {
          print(
            'AppController: Connected but no groups, re-applying profile...',
          );
          try {
            await applyProfile(
              silence: true,
            ).timeout(const Duration(seconds: 5));
          } catch (e) {
            print('AppController: Apply profile timed out: $e');
          }

          if (getCurrentGroups().isEmpty) {
            print(
              'AppController: Still no groups after re-apply, disconnecting...',
            );
            await updateStatus(false);
          } else {
            await updateStatus(true);
          }
        }
      } else {
        // Verification failed
        print(
          'AppController: Service claimed running but Core verification failed. Forcing Disconnected.',
        );
        _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
        if (isServiceRunning) {
          await globalState.handleStop();
        }
      }
    } else if (autoRun) {
      print('AppController: AutoRun is enabled, starting...');
      await updateStatus(true);
    } else {
      print('AppController: Not running, idle.');
      _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      addCheckIpNumDebounce();
    }
  }

  void setDelay(Delay delay) {
    _ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  Future<void> handleLogout() async {
    final context = globalState.navigatorKey.currentContext;
    if (context != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('退出登录'),
            content: const Text('确定要退出当前账号吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      if (confirm != true) return;
    }

    // 停止系统代理，防止退出后无法上网
    await stopSystemProxy();

    final profiles = _ref.read(profilesProvider);
    for (final profile in profiles) {
      await deleteProfile(profile.id);
    }

    // 强制更新UI状态为未连接，避免UI锁死
    _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;

    // 强制关闭内核，带超时机制
    try {
      await coreController.shutdown().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          commonPrint.log(
            'Shutdown timed out during logout',
            logLevel: LogLevel.warning,
          );
        },
      );
    } catch (e) {
      commonPrint.log(
        'Failed to shutdown core: $e',
        logLevel: LogLevel.warning,
      );
    }

    // Ensure the state is updated
    await Future.delayed(const Duration(milliseconds: 100));

    if (_ref.read(profilesProvider).isEmpty) {
      if (context != null && context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const V2BoardLoginPage()),
          (route) => false,
        );
      }
    } else {
      _ref.read(currentPageLabelProvider.notifier).value = PageLabel.dashboard;
    }
  }

  Future<void> stopSystemProxy() async {
    // 使用 updateStatus(false) 执行完整的停止逻辑
    // 包括：禁用 TUN、关闭系统代理、停止核心监听等
    await updateStatus(false);
  }

  Future<void> startSystemProxy() async {
    await updateStatus(true);
  }

  void toPage(PageLabel pageLabel) {
    if (pageLabel == PageLabel.logout) {
      handleLogout();
      return;
    }
    _ref.read(currentPageLabelProvider.notifier).value = pageLabel;
  }

  void toProfiles() {
    toPage(PageLabel.profiles);
  }

  void initLink() {
    linkManager.initAppLinksListen((url) async {
      final res = await globalState.showMessage(
        title: '${appLocalizations.add}${appLocalizations.profile}',
        message: TextSpan(
          children: [
            TextSpan(text: appLocalizations.doYouWantToPass),
            TextSpan(
              text: ' $url ',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            TextSpan(
              text: '${appLocalizations.create}${appLocalizations.profile}',
            ),
          ],
        ),
      );

      if (res != true) {
        return;
      }
      addProfileFormURL(url);
    });
  }

  Future<bool> showDisclaimer() async {
    return await globalState.showCommonDialog<bool>(
          dismissible: false,
          child: CommonDialog(
            title: appLocalizations.disclaimer,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop<bool>(false);
                },
                child: Text(appLocalizations.exit),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop<bool>(true);
                },
                child: Text(appLocalizations.agree),
              ),
            ],
            child: Text(appLocalizations.disclaimerDesc),
          ),
        ) ??
        false;
  }

  Future<void> _showCrashlyticsTip() async {
    if (!system.isAndroid) {
      return;
    }
    if (_ref.read(appSettingProvider).crashlyticsTip) {
      return;
    }
    await globalState.showMessage(
      title: appLocalizations.dataCollectionTip,
      cancelable: false,
      message: TextSpan(text: appLocalizations.dataCollectionContent),
    );
    _ref
        .read(appSettingProvider.notifier)
        .updateState((state) => state.copyWith(crashlyticsTip: true));
  }

  Future<void> _handlerDisclaimer() async {
    if (_ref.read(appSettingProvider).disclaimerAccepted) {
      return;
    }
    final isDisclaimerAccepted = await showDisclaimer();
    if (!isDisclaimerAccepted) {
      await handleExit();
    }
    _ref
        .read(appSettingProvider.notifier)
        .updateState((state) => state.copyWith(disclaimerAccepted: true));
    return;
  }

  Future<void> addProfileFormURL(
    String url, {
    String? jwt,
    bool skipNavigation = false,
  }) async {
    if (!skipNavigation) {
      if (globalState.navigatorKey.currentState?.canPop() ?? false) {
        globalState.navigatorKey.currentState?.popUntil(
          (route) => route.isFirst,
        );
      }
      toProfiles();
    }

    var profile = Profile.normal(url: url);
    if (jwt != null) {
      profile = profile.copyWith(jwt: jwt);
    }

    final updatedProfile = await safeRun(
      () async {
        return await profile.update();
      },
      needLoading: true,
      title: '${appLocalizations.add}${appLocalizations.profile}',
    );

    // If update succeeded, use the updated profile
    // If update failed but we have JWT, still save the profile so user can purchase plans
    if (updatedProfile != null) {
      await addProfile(updatedProfile);
    } else if (jwt != null) {
      // Save profile with JWT even without subscription data
      await addProfile(profile);
      if (!skipNavigation) {
        context.showNotifier('登录成功，请购买套餐后刷新订阅');
      }
    }
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await safeRun(picker.pickerFile);
    final bytes = platformFile?.bytes;
    if (bytes == null) {
      return;
    }
    if (!context.mounted) return;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    toProfiles();

    final profile = await safeRun(
      () async {
        await Future.delayed(const Duration(milliseconds: 300));
        return await Profile.normal(label: platformFile?.name).saveFile(bytes);
      },
      needLoading: true,
      title: '${appLocalizations.add}${appLocalizations.profile}',
    );
    if (profile != null) {
      await addProfile(profile);
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  void updateViewSize(Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref.read(viewSizeProvider.notifier).value = size;
    });
  }

  void setProvider(ExternalProvider? provider) {
    _ref.read(providersProvider.notifier).setProvider(provider);
  }

  Future<void> clearEffect(String profileId) async {
    final profilePath = await appPath.getProfilePath(profileId);
    final providersDirPath = await appPath.getProvidersDirPath(profileId);
    return await Isolate.run(() async {
      final profileFile = File(profilePath);
      final isExists = await profileFile.exists();
      if (isExists) {
        profileFile.delete(recursive: true);
      }
      await coreController.deleteFile(providersDirPath);
    });
  }

  void updateTun() {
    _ref
        .read(patchClashConfigProvider.notifier)
        .updateState((state) => state.copyWith.tun(enable: !state.tun.enable));
  }

  void updateSystemProxy() {
    _ref
        .read(networkSettingProvider.notifier)
        .updateState(
          (state) => state.copyWith(systemProxy: !state.systemProxy),
        );
  }

  void handleCoreDisconnected() {
    _ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
  }

  Future<List<Package>> getPackages() async {
    if (_ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    if (_ref.read(packagesProvider).isEmpty) {
      _ref.read(packagesProvider.notifier).value =
          await app?.getPackages() ?? [];
    }
    return _ref.read(packagesProvider);
  }

  void updateStart() {
    updateStatus(!_ref.read(isStartProvider));
  }

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final SelectedMap selectedMap = Map.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      _ref
          .read(profilesProvider.notifier)
          .setProfile(currentProfile.copyWith(selectedMap: selectedMap));
      savePreferencesDebounce();
    }
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile == null) {
      return;
    }
    _ref
        .read(profilesProvider.notifier)
        .setProfile(currentProfile.copyWith(unfoldSet: value));
  }

  void changeMode(Mode mode) {
    _ref
        .read(patchClashConfigProvider.notifier)
        .updateState((state) => state.copyWith(mode: mode));
    if (mode == Mode.global) {
      updateCurrentGroupName(GroupName.GLOBAL.name);
    }
    addCheckIpNumDebounce();
  }

  void updateAutoLaunch() {
    _ref
        .read(appSettingProvider.notifier)
        .updateState((state) => state.copyWith(autoLaunch: !state.autoLaunch));
  }

  Future<void> updateVisible() async {
    final visible = await window?.isVisible;
    if (visible != null && !visible) {
      window?.show();
    } else {
      window?.hide();
    }
  }

  void updateMode() {
    _ref.read(patchClashConfigProvider.notifier).updateState((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) {
        return null;
      }
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<bool> exportLogs() async {
    final logsRaw = _ref.read(logsProvider).list.map((item) => item.toString());
    final data = await Isolate.run<List<int>>(() async {
      final logsRawString = logsRaw.join('\n');
      return utf8.encode(logsRawString);
    });
    return await picker.saveFile(utils.logFile, Uint8List.fromList(data)) !=
        null;
  }

  Future<List<int>> backupData() async {
    final homeDirPath = await appPath.homeDirPath;
    final profilesPath = await appPath.profilesPath;
    final configJson = globalState.config.toJson();
    return Isolate.run<List<int>>(() async {
      final archive = Archive();
      archive.addTextFile('config.json', configJson);
      archive.addDirectoryToArchive(profilesPath, homeDirPath);
      final zipEncoder = ZipEncoder();
      return zipEncoder.encode(archive);
    });
  }

  Future<void> updateTray([bool focus = false]) async {
    tray?.update(trayState: _ref.read(trayStateProvider));
  }

  Future<void> recoveryData(
    List<int> data,
    RecoveryOption recoveryOption,
  ) async {
    final archive = await Isolate.run<Archive>(() {
      final zipDecoder = ZipDecoder();
      return zipDecoder.decodeBytes(data);
    });
    final homeDirPath = await appPath.homeDirPath;
    final configs = archive.files
        .where((item) => item.name.endsWith('.json'))
        .toList();
    final profiles = archive.files.where(
      (item) => !item.name.endsWith('.json'),
    );
    final configIndex = configs.indexWhere(
      (config) => config.name == 'config.json',
    );
    if (configIndex == -1) throw 'invalid backup file';
    final configFile = configs[configIndex];
    var tempConfig = Config.compatibleFromJson(
      json.decode(utf8.decode(configFile.content)),
    );
    for (final profile in profiles) {
      final filePath = join(homeDirPath, profile.name);
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(profile.content);
    }
    final clashConfigIndex = configs.indexWhere(
      (config) => config.name == 'clashConfig.json',
    );
    if (clashConfigIndex != -1) {
      final clashConfigFile = configs[clashConfigIndex];
      tempConfig = tempConfig.copyWith(
        patchClashConfig: ClashConfig.fromJson(
          json.decode(utf8.decode(clashConfigFile.content)),
        ),
      );
    }
    _recovery(tempConfig, recoveryOption);
  }

  void _recovery(Config config, RecoveryOption recoveryOption) {
    final recoveryStrategy = _ref.read(appSettingProvider).recoveryStrategy;
    final profiles = config.profiles;
    if (recoveryStrategy == RecoveryStrategy.override) {
      _ref.read(profilesProvider.notifier).value = profiles;
    } else {
      for (final profile in profiles) {
        _ref.read(profilesProvider.notifier).setProfile(profile);
      }
    }
    final onlyProfiles = recoveryOption == RecoveryOption.onlyProfiles;
    if (!onlyProfiles) {
      _ref.read(patchClashConfigProvider.notifier).value =
          config.patchClashConfig;
      _ref.read(appSettingProvider.notifier).value = config.appSetting;
      _ref.read(currentProfileIdProvider.notifier).value =
          config.currentProfileId;
      _ref.read(appDAVSettingProvider.notifier).value = config.dav;
      _ref.read(themeSettingProvider.notifier).value = config.themeProps;
      _ref.read(windowSettingProvider.notifier).value = config.windowProps;
      _ref.read(vpnSettingProvider.notifier).value = config.vpnProps;
      _ref.read(proxiesStyleSettingProvider.notifier).value =
          config.proxiesStyle;
      _ref.read(overrideDnsProvider.notifier).value = config.overrideDns;
      _ref.read(networkSettingProvider.notifier).value = config.networkProps;
      _ref.read(hotKeyActionsProvider.notifier).value = config.hotKeyActions;
      _ref.read(scriptStateProvider.notifier).value = config.scriptProps;
    }
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile == null) {
      _ref.read(currentProfileIdProvider.notifier).value = profiles.first.id;
    }
  }

  Future<T?> safeRun<T>(
    FutureOr<T> Function() futureFunction, {
    String? title,
    bool needLoading = false,
    bool silence = true,
  }) async {
    final realSilence = needLoading == true ? true : silence;
    try {
      if (needLoading) {
        _ref.read(loadingProvider.notifier).value = true;
      }
      final res = await futureFunction();
      return res;
    } catch (e) {
      commonPrint.log('$title===> $e', logLevel: LogLevel.warning);
      if (realSilence) {
        globalState.showNotifier(e.toString());
      } else {
        globalState.showMessage(
          title: title ?? appLocalizations.tip,
          message: TextSpan(text: e.toString()),
        );
      }
      return null;
    } finally {
      if (needLoading) {
        _ref.read(loadingProvider.notifier).value = false;
      }
    }
  }
}
