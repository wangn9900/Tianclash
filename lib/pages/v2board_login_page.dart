import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/v2board_service.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/common/image_upload_service.dart';
import 'home.dart';

// TODO: Replace with actual OSS URL
const String kOssConfigUrl = 'https://oss.tianque.cc/oss_config.txt';
const List<String> kBackupUrls = [
  'https://154.219.96.225:8443',
  'https://154.219.96.225:2621',
  'https://150.241.207.176:8443',
];
const String kFallbackUrl = 'https://150.241.207.176:8443';

enum LoginMode { login, register, forgotPassword }

class V2BoardLoginPage extends StatefulWidget {
  const V2BoardLoginPage({super.key});

  @override
  State<V2BoardLoginPage> createState() => _V2BoardLoginPageState();
}

class _V2BoardLoginPageState extends State<V2BoardLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _verifyCodeController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  
  bool _loading = false;
  bool _rememberMe = false;
  bool _autoLogin = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  LoginMode _loginMode = LoginMode.login;

  Future<String> _fetchBaseUrl() async {
    // Try OSS Config first
    try {
      final dio = Dio();
      print('Fetching OSS config from: $kOssConfigUrl');
      final response = await dio.get(
        kOssConfigUrl,
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      print('OSS Config Response: ${response.statusCode}');
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data.toString().isNotEmpty) {
        
        print('OSS Config Content: ${response.data}');
        String configContent = response.data.toString();
        try {
          // Try Base64 decode
          final decoded = utf8.decode(base64Decode(configContent.replaceAll(RegExp(r'\s'), '')));
          print('Decoded OSS Config: $decoded');
          configContent = decoded;
        } catch (e) {
          print('Base64 decode failed, using original content: $e');
        }

        final lines = configContent
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        // Extract ImgBB Key if present (Format: IMGBB:key)
        final imgbbLine = lines.firstWhere(
            (e) => e.toUpperCase().startsWith('IMGBB:'), 
            orElse: () => '');
        if (imgbbLine.isNotEmpty) {
          final key = imgbbLine.substring(6).trim();
          if (key.isNotEmpty) {
            print('Found ImgBB Key in OSS config');
            ImageUploadService().imgbbApiKey = key;
          }
        }

        final urls = lines
            .where((e) => e.startsWith('http'))
            .toList();

        if (urls.isNotEmpty) {
          for (final url in urls) {
            if (await _checkUrlAvailability(url)) {
              print('Found available URL from OSS: $url');
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('通过 OSS 远程配置连接成功！'), duration: Duration(seconds: 1)),
                );
              }
              return url;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch OSS URL: $e');
    }

    // Try Backup URLs if OSS fails
    print('OSS fetch failed or no valid URLs. Trying backup URLs...');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OSS 连接失败，正在尝试备用连接...'), duration: Duration(seconds: 1)),
      );
    }
    
    for (final url in kBackupUrls) {
      if (await _checkUrlAvailability(url)) {
        print('Found available backup URL: $url');
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已连接到备用服务器'), duration: Duration(seconds: 1)),
          );
        }
        return url;
      }
    }

    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有连接尝试失败，使用回退地址'), duration: Duration(seconds: 1)),
      );
    }
    return kFallbackUrl;
  }

  Future<bool> _checkUrlAvailability(String baseUrl) async {
    try {
      final dio = Dio();
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
      
      print('Checking availability for: $baseUrl');
      // Try to fetch comm config as a health check
      final response = await dio.get(
        '$baseUrl/api/v1/guest/comm/config',
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      print('Response for $baseUrl: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('Error checking $baseUrl: $e');
      return false;
    }
  }

  Future<void> _sendVerifyCode() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).enterEmail)),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    final baseUrl = await _fetchBaseUrl();
    final service = V2BoardService(userAgent: globalState.packageInfo.ua);
    final success = await service.sendEmailVerify(baseUrl, _emailController.text);

    setState(() {
      _loading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '验证码已发送' : '发送失败'),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
    });

    final baseUrl = await _fetchBaseUrl();
    final service = V2BoardService(userAgent: globalState.packageInfo.ua);

    if (_loginMode == LoginMode.login) {
      final result = await service.loginAndGetSubscribeUrl(
        baseUrl,
        _emailController.text,
        _passwordController.text,
      );
      _handleLoginResult(result);
    } else if (_loginMode == LoginMode.register) {
      final result = await service.register(
        baseUrl,
        _emailController.text,
        _passwordController.text,
        _verifyCodeController.text,
        inviteCode: _inviteCodeController.text,
      );
      _handleLoginResult(result);
    } else if (_loginMode == LoginMode.forgotPassword) {
      final success = await service.forgetPassword(
        baseUrl,
        _emailController.text,
        _passwordController.text,
        _verifyCodeController.text,
      );
      setState(() {
        _loading = false;
      });
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码重置成功，请登录')),
        );
        setState(() {
          _loginMode = LoginMode.login;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('v2board_remember_me') ?? false;
      _autoLogin = prefs.getBool('v2board_auto_login') ?? false;
      
      if (_rememberMe) {
        _emailController.text = prefs.getString('v2board_email') ?? '';
        _passwordController.text = prefs.getString('v2board_password') ?? '';
      }
    });

    if (_autoLogin && _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty) {
      _submit();
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('v2board_remember_me', _rememberMe);
    await prefs.setBool('v2board_auto_login', _autoLogin);
    
    if (_rememberMe) {
      await prefs.setString('v2board_email', _emailController.text);
      await prefs.setString('v2board_password', _passwordController.text);
    } else {
      await prefs.remove('v2board_email');
      await prefs.remove('v2board_password');
    }
  }

  Future<void> _handleLoginResult(({String token, String url})? result) async {
    setState(() {
      _loading = false;
    });

    if (result != null && mounted) {
      await _saveCredentials();
      await globalState.appController
          .addProfileFormURL(result.url, jwt: result.token);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).loginFailed)),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    // Fixed Scaffold syntax
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 600;
          return Container(
            decoration: !isDesktop
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1a237e), // Deep Blue
                        Color(0xFF000000), // Black
                      ],
                    ),
                  )
                : null,
            child: Row(
              children: [
                if (isDesktop)
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1a237e), // Deep Blue
                            Color(0xFF000000), // Black
                          ],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '天阙 VPN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '安全高效的网络管理工具',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 20,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 60),
                            Text(
                              '© 2026 天阙 VPN. 保留所有权利。',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              // Right Side - Form
              Expanded(
                flex: 1,
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 0 : 24,
                      vertical: isDesktop ? 0 : 40,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      padding: const EdgeInsets.all(40),
                      decoration: isDesktop
                          ? null
                          : BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _loginMode == LoginMode.login
                                  ? '登录'
                                  : _loginMode == LoginMode.register
                                      ? '注册账号'
                                      : '找回密码',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _loginMode == LoginMode.login
                                  ? '欢迎回来,请登录您的账号'
                                  : _loginMode == LoginMode.register
                                      ? '创建一个新账号'
                                      : '重置您的密码',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 40),
                            const Text('邮箱', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                hintText: '请输入邮箱',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return AppLocalizations.of(context).enterEmail;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            if (_loginMode != LoginMode.login) ...[
                              const Text('验证码', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _verifyCodeController,
                                      decoration: const InputDecoration(
                                        hintText: '请输入验证码',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.verified_user_outlined),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return '请输入验证码';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  OutlinedButton(
                                    onPressed: _loading ? null : _sendVerifyCode,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                    ),
                                    child: const Text('发送'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],
                            Text(
                              _loginMode == LoginMode.forgotPassword ? '新密码' : '密码',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  hintText: _loginMode == LoginMode.forgotPassword ? '请输入新密码' : '请输入密码',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return AppLocalizations.of(context).enterPassword;
                                }
                                return null;
                              },
                            ),
                            if (_loginMode == LoginMode.register) ...[
                              const SizedBox(height: 24),
                              const Text('确认密码', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirmPassword,
                                decoration: InputDecoration(
                                  hintText: '请再次输入密码',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirmPassword = !_obscureConfirmPassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '请确认密码';
                                  }
                                  if (value != _passwordController.text) {
                                    return '两次输入的密码不一致';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              const Text('邀请码 (可选)', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _inviteCodeController,
                                decoration: const InputDecoration(
                                  hintText: '请输入邀请码',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.card_giftcard),
                                ),
                              ),
                            ],
                            if (_loginMode == LoginMode.login) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
                                  ),
                                  const Text('记住我'),
                                  const Spacer(),
                                  Checkbox(
                                    value: _autoLogin,
                                    onChanged: (value) {
                                      setState(() {
                                        _autoLogin = value ?? false;
                                      });
                                    },
                                  ),
                                  const Text('自动登录'),
                                ],
                              ),
                            ],
                            const SizedBox(height: 32),
                            FilledButton(
                              onPressed: _loading ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0D47A1),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _loginMode == LoginMode.login
                                          ? '登录'
                                          : _loginMode == LoginMode.register
                                              ? '注册'
                                              : '重置密码',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                            ),
                            const SizedBox(height: 24),
                            if (_loginMode == LoginMode.login)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      _formKey.currentState?.reset();
                                      setState(() {
                                        _loginMode = LoginMode.register;
                                      });
                                    },
                                    icon: const Icon(Icons.person_add_outlined),
                                    label: const Text('注册账号'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      _formKey.currentState?.reset();
                                      setState(() {
                                        _loginMode = LoginMode.forgotPassword;
                                      });
                                    },
                                    icon: const Icon(Icons.help_outline),
                                    label: const Text('忘记密码'),
                                  ),
                                ],
                              )
                            else
                              Center(
                                child: TextButton.icon(
                                  onPressed: () {
                                    _formKey.currentState?.reset();
                                    setState(() {
                                      _loginMode = LoginMode.login;
                                    });
                                  },
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('返回登录'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  }
}
