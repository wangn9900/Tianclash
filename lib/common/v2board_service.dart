import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class V2BoardService {
  final Dio _dio = Dio();

  V2BoardService({String? userAgent}) {
    _dio.options.validateStatus = (status) {
      return status != null && status < 500;
    };
    // 添加默认请求头以支持 Cloudflare CDN
    _dio.options.headers = {
      'User-Agent': userAgent ?? 'FlClash/1.0 (Dart)',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    // 增加超时时间以适应 Cloudflare CDN
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.options.sendTimeout = const Duration(seconds: 15);
    // 允许重定向
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 5;
    
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return client;
    };
  }


  Future<({String url, String token})?> loginAndGetSubscribeUrl(
      String baseUrl, String email, String password) async {
    print('V2BoardService: loginAndGetSubscribeUrl called with baseUrl: $baseUrl');
    var realBaseUrl = baseUrl;
    if (realBaseUrl.startsWith('BASE64:')) {
      final base64Str = realBaseUrl.substring(7);
      try {
        realBaseUrl = utf8.decode(base64.decode(base64Str));
        print('V2BoardService: Decoded BASE64 URL: $realBaseUrl');
      } catch (_) {}
    }

    // Try to fetch as remote config
    try {
      print('V2BoardService: Attempting to fetch as remote config: $realBaseUrl');
      final response = await _dio.get(realBaseUrl,
          options: Options(responseType: ResponseType.plain));
      if (response.statusCode == 200) {
        final content = response.data.toString();
        print('V2BoardService: Remote config fetched. Content: $content');
        final lines = content.split('\n');
        final urls = lines
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .where((e) => e.startsWith('http') || e.startsWith('BASE64:'))
            .toList();

        print('V2BoardService: Parsed ${urls.length} URLs from config');

        if (urls.isNotEmpty) {
          for (var url in urls) {
            print('V2BoardService: Processing candidate URL: $url');
            var candidateUrl = url;
            if (candidateUrl.startsWith('BASE64:')) {
              final base64Str = candidateUrl.substring(7);
              try {
                candidateUrl = utf8.decode(base64.decode(base64Str));
                print('V2BoardService: Decoded candidate BASE64 URL: $candidateUrl');
              } catch (_) {
                continue;
              }
            }
            print('V2BoardService: Trying login with: $candidateUrl');
            final result = await _login(candidateUrl, email, password);
            if (result != null) {
              print('V2BoardService: Login successful with: $candidateUrl');
              return result;
            } else {
              print('V2BoardService: Login failed with: $candidateUrl');
            }
          }
           
           if (urls.length > 1 || (urls.length == 1 && urls.first != realBaseUrl)) {
             print('V2BoardService: All candidates failed. Returning null.');
             return null; 
           }
        }
      }
    } catch (e) {
      print('V2BoardService: Fetch remote config failed or not a config file: $e');
    }

    print('V2BoardService: Fallback to direct login with: $realBaseUrl');
    return await _login(realBaseUrl, email, password);
  }

  Future<({String url, String token})?> _login(
      String baseUrl, String email, String password) async {
    final cleanBaseUrl =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final loginUrl = '$cleanBaseUrl/api/v1/passport/auth/login';

    try {
      final response = await _dio.post(loginUrl, data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200 &&
          response.data['data'] != null &&
          response.data['data']['auth_data'] != null) {
        final authData = response.data['data']['auth_data'];
        final subscribeUrl = await _getSubscribeUrl(cleanBaseUrl, authData);
        if (subscribeUrl != null) {
          return (url: subscribeUrl, token: authData as String);
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Future<String?> _getSubscribeUrl(String baseUrl, String authData) async {
    final url = '$baseUrl/api/v1/user/getSubscribe';

    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': authData,
          }));

      if (response.statusCode == 200 &&
          response.data['data'] != null &&
          response.data['data']['subscribe_url'] != null) {
        return response.data['data']['subscribe_url'];
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Future<List<dynamic>?> fetchPlans(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/plan/fetch';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Future<dynamic> verifyCoupon(
      String baseUrl, String token, String code, int planId) async {
    final url = '$baseUrl/api/v1/user/coupon/check';
    try {
      final response = await _dio.post(url,
          data: {'code': code, 'plan_id': planId},
          options: Options(headers: {
            'Authorization': token,
          }));
      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Future<String?> submitOrder(String baseUrl, String token, int planId,
      String period, {String? couponCode}) async {
    final url = '$baseUrl/api/v1/user/order/save';
    try {
      final data = {
        'plan_id': planId,
        'period': period,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      };
      print('Submitting order to $url with data: $data'); // Debug log
      final response = await _dio.post(url,
          data: FormData.fromMap(data),
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Order submission response: ${response.data}'); // Debug log
      if (response.statusCode == 200 && response.data['data'] != null) {
        // V2Board usually returns the trade_no as a string in 'data'
        // or sometimes { "trade_no": "..." }
        final responseData = response.data['data'];
        if (responseData is String) {
          return responseData;
        } else if (responseData is Map && responseData['trade_no'] != null) {
          return responseData['trade_no'].toString();
        }
      }
    } catch (e) {
      print('Error submitting order: $e'); // Debug log
      if (e is DioException) {
        print('DioError response: ${e.response?.data}');
      }
    }
    return null;
  }

  Future<List<dynamic>?> fetchOrders(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/order/fetch';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Fetch orders response: ${response.data}'); // Debug log
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching orders: $e');
    }
    return null;
  }

  Future<bool> cancelOrder(String baseUrl, String token, String tradeNo) async {
    final url = '$baseUrl/api/v1/user/order/cancel';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({'trade_no': tradeNo}),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error cancelling order: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> getUserInfo(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/info';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching user info: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getCommConfig(String baseUrl) async {
    final url = '$baseUrl/api/v1/guest/comm/config';
    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching comm config: $e');
    }
    return null;
  }
  
  Future<bool> changePassword(String baseUrl, String token, String oldPassword, String newPassword) async {
    final url = '$baseUrl/api/v1/user/password/update';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'old_password': oldPassword,
            'new_password': newPassword,
          }),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error changing password: $e');
    }
    return false;
  }

  Future<List<dynamic>?> getPaymentMethods(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/order/getPaymentMethod';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Get payment methods response: ${response.data}'); // Debug log
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error getting payment methods: $e');
    }
    return null;
  }

  Future<dynamic> checkoutOrder(
      String baseUrl, String token, String tradeNo, int methodId) async {
    final url = '$baseUrl/api/v1/user/order/checkout';
    try {
      print('Checkout request: trade_no=$tradeNo, method=$methodId'); // Debug log
      
      // 构造Referer URL（PaymentService需要用它来构建return_url）
      final uri = Uri.parse(baseUrl);
      final refererUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/';
      
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'trade_no': tradeNo,
            'method': methodId,
          }),
          options: Options(headers: {
            'Authorization': token,
            'Referer': refererUrl, // 添加Referer头
          }));
      print('Checkout response: ${response.data}'); // Debug log
      if (response.statusCode == 200) {
        // 返回完整的响应数据，包含 type 和 data 字段
        return response.data;
      }
    } catch (e) {
      print('Error checking out: $e');
      if (e is DioException) {
        print('Response data: ${e.response?.data}');
        print('Response status: ${e.response?.statusCode}');
      }
      rethrow; // 重新抛出异常以便上层处理
    }
    return null;
  }

  Future<bool> sendEmailVerify(String baseUrl, String email) async {
    final url = '$baseUrl/api/v1/passport/comm/sendEmailVerify';
    try {
      final response = await _dio.post(url, data: FormData.fromMap({'email': email}));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error sending email verify: $e');
    }
    return false;
  }

  Future<({String url, String token})?> register(
      String baseUrl, String email, String password, String verifyCode,
      {String? inviteCode}) async {
    final url = '$baseUrl/api/v1/passport/auth/register';
    try {
      final data = {
        'email': email,
        'password': password,
        'email_code': verifyCode,
        if (inviteCode != null && inviteCode.isNotEmpty)
          'invite_code': inviteCode,
      };
      final response = await _dio.post(url, data: FormData.fromMap(data));

      if (response.statusCode == 200 &&
          response.data['data'] != null &&
          response.data['data']['auth_data'] != null) {
        final authData = response.data['data']['auth_data'];
        final subscribeUrl = await _getSubscribeUrl(baseUrl, authData);
        if (subscribeUrl != null) {
          return (url: subscribeUrl, token: authData as String);
        }
      }
    } catch (e) {
      print('Error registering: $e');
    }
    return null;
  }

  Future<bool> forgetPassword(
      String baseUrl, String email, String password, String verifyCode) async {
    final url = '$baseUrl/api/v1/passport/auth/forget';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'email': email,
            'password': password,
            'email_code': verifyCode,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error forgetting password: $e');
    }
    return false;
  }

  Future<dynamic> getTrafficLog(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/stat/getTrafficLog';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching traffic log: $e');
    }
    return null;
  }

  Future<List<dynamic>?> fetchTickets(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/ticket/fetch';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching tickets: $e');
    }
    return null;
  }

  Future<dynamic> getTicketDetail(String baseUrl, String token, int id) async {
    final url = '$baseUrl/api/v1/user/ticket/fetch?id=$id';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Get ticket detail response: ${response.data}'); // Debug log
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching ticket detail: $e');
    }
    return null;
  }

  Future<bool> createTicket(String baseUrl, String token, String subject, String level, String message) async {
    final url = '$baseUrl/api/v1/user/ticket/save';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'subject': subject,
            'level': level,
            'message': message,
          }),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error creating ticket: $e');
    }
    return false;
  }

  Future<bool> replyTicket(String baseUrl, String token, int id, String message) async {
    final url = '$baseUrl/api/v1/user/ticket/reply';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'id': id,
            'message': message,
          }),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error replying ticket: $e');
    }
    return false;
  }

  Future<bool> closeTicket(String baseUrl, String token, int id) async {
    final url = '$baseUrl/api/v1/user/ticket/close';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'id': id,
          }),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error closing ticket: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> getInviteData(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/invite/fetch';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Get invite data response: ${response.data}'); // Debug log
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching invite data: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getInviteDetails(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/invite/details';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Get invite details response: ${response.data}'); // Debug log
      if (response.statusCode == 200 && response.data['data'] != null) {
        return response.data['data'];
      }
    } catch (e) {
      print('Error fetching invite details: $e');
    }
    return null;
  }

  Future<bool> generateInviteCode(String baseUrl, String token) async {
    final url = '$baseUrl/api/v1/user/invite/save';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      print('Generate invite code response: ${response.data}'); // Debug log
      return response.statusCode == 200;
    } catch (e) {
      print('Error generating invite code: $e');
      return false;
    }
  }


  Future<bool> transferCommission(String baseUrl, String token, double amount) async {
    final url = '$baseUrl/api/v1/user/invite/transfer';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'amount': amount,
          }),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error transferring commission: $e');
      return false;
    }
  }

  Future<bool> withdrawCommission(String baseUrl, String token, double amount, String method, String account) async {
    final url = '$baseUrl/api/v1/user/invite/withdraw';
    try {
      final response = await _dio.post(url,
          data: FormData.fromMap({
            'amount': amount,
            'withdraw_method': method,
            'withdraw_account': account,
          }),
          options: Options(headers: {
            'Authorization': token,
          }));
      return response.statusCode == 200 && response.data['data'] == true;
    } catch (e) {
      print('Error withdrawing commission: $e');
      return false;
    }
  }

  Future<String?> submitDepositOrder(String baseUrl, String token, int amount) async {
    final url = '$baseUrl/api/v1/user/order/save';
    try {
      final data = {
        'plan_id': 0,
        'deposit_amount': amount,
        'period': 'deposit',
      };
      print('Submitting deposit order to $url with data: $data');
      final response = await _dio.post(url,
          data: data,
          options: Options(headers: {
            'Authorization': token,
            'Content-Type': 'application/json',
          }));
      
      if (response.statusCode == 200 && response.data['data'] != null) {
        // V2Board usually returns the trade_no as a string in 'data'
        // or sometimes { "trade_no": "..." }
        final responseData = response.data['data'];
        if (responseData is String) {
          return responseData;
        } else if (responseData is Map && responseData['trade_no'] != null) {
          return responseData['trade_no'].toString();
        }
      }
    } catch (e) {
      print('Error submitting deposit order: $e');
      if (e is DioException && e.response?.data != null) {
        final message = e.response?.data['message'];
        if (message != null) {
          throw message;
        }
      }
      rethrow;
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchNotices(String baseUrl, String token, {int current = 1, int pageSize = 5}) async {
    final url = '$baseUrl/api/v1/user/notice/fetch?current=$current&pageSize=$pageSize';
    try {
      final response = await _dio.get(url,
          options: Options(headers: {
            'Authorization': token,
          }));
      if (response.statusCode == 200 && response.data['data'] != null) {
        return {
          'data': response.data['data'],
          'total': response.data['total'] ?? 0,
        };
      }
    } catch (e) {
      print('Error fetching notices: $e');
    }
    return null;
  }
}
