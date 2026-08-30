import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguageController extends ChangeNotifier {
  AppLanguageController._(this._languageCode);

  static const _preferenceKey = 'app_language';
  static const supportedLanguageCodes = ['en', 'zh', 'ms'];

  String _languageCode;

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);

  static Future<AppLanguageController> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedCode = preferences.getString(_preferenceKey);
    final deviceCode = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final initialCode = supportedLanguageCodes.contains(savedCode)
        ? savedCode!
        : supportedLanguageCodes.contains(deviceCode)
            ? deviceCode
            : 'en';
    return AppLanguageController._(initialCode);
  }

  Future<void> setLanguage(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode) ||
        languageCode == _languageCode) {
      return;
    }

    _languageCode = languageCode;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, languageCode);
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController controllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope is missing above this context.');
    return scope!.notifier!;
  }
}

extension AppTranslations on BuildContext {
  AppLanguageController get languageController =>
      AppLanguageScope.controllerOf(this);

  String tr(String key) {
    final languageCode = languageController.languageCode;
    return _translations[languageCode]?[key] ?? key;
  }
}

const Map<String, Map<String, String>> _translations = {
  'zh': {
    'Journey': '旅程',
    'Stations': '车站',
    'AI Crowd': 'AI 人流',
    'Profile': '个人资料',
    'Analytics': '数据分析',
    'Transport Data': '交通数据',
    'Analytics Centre': '数据分析中心',
    'coming soon': '即将推出',
    'Create Account': '创建账户',
    'Welcome Back': '欢迎回来',
    'Create your NextRoute account': '创建你的 NextRoute 账户',
    'Sign in to continue to NextRoute': '登录以继续使用 NextRoute',
    'Display name': '显示名称',
    'Email': '电子邮箱',
    'Password': '密码',
    'Register': '注册',
    'Sign In': '登录',
    'Already have an account? Sign In': '已有账户？立即登录',
    'New user? Create an account': '新用户？创建账户',
    'Verify your email': '验证你的电子邮箱',
    'Enter the 8-digit code sent to': '请输入发送至以下邮箱的 8 位验证码',
    'Verification code': '验证码',
    'Verify Code': '验证',
    'Resend Code': '重新发送验证码',
    'Resend code in': '可重新发送时间：',
    'Change email address': '更改电子邮箱地址',
    'Please enter the 8-digit verification code.': '请输入 8 位验证码。',
    'Verification code resent.': '验证码已重新发送。',
    'Email verified successfully.': '电子邮箱验证成功。',
    'Confirm new email': '确认新电子邮箱',
    'Enter the 8-digit code sent to your new email':
        '请输入发送至新电子邮箱的 8 位验证码',
    'Turn off Secure email change in Supabase, then request a new code.':
        '请在 Supabase 关闭 Secure email change，然后重新获取验证码。',
    'Email change is still pending. Confirm the message sent to your old email or disable Secure email change.':
        '邮箱修改仍待确认。请确认发送到旧邮箱的邮件，或关闭 Secure email change。',
    'Please enter your name.': '请输入你的姓名。',
    'Please enter a valid email address.': '请输入有效的电子邮箱地址。',
    'Password must contain at least 6 characters.': '密码必须至少包含 6 个字符。',
    'Account created. Please confirm your email.': '账户已创建，请确认你的电子邮箱。',
    'Account created successfully.': '账户创建成功。',
    'Signed in successfully.': '登录成功。',
    'Something went wrong. Please try again.': '发生错误，请重试。',
    'My Profile': '我的个人资料',
    'Edit Profile': '编辑个人资料',
    'Member ID': '会员编号',
    'Your unique member ID cannot be changed.': '你的唯一会员编号无法修改。',
    'Location': '地区',
    'Phone number': '电话号码',
    'Cancel': '取消',
    'Save': '保存',
    'Display name cannot be empty.': '显示名称不能为空。',
    'Display name must be 50 characters or fewer.': '显示名称不能超过 50 个字符。',
    'Location must be 100 characters or fewer.': '地区不能超过 100 个字符。',
    'Use 10–11 digits starting with 01.': '请输入以 01 开头的 10–11 位数字。',
    'Unable to load profile.': '无法载入个人资料。',
    'Unable to update profile.': '无法更新个人资料。',
    'Profile updated successfully.': '个人资料更新成功。',
    'Profile saved. Check your email to confirm the new address.':
        '个人资料已保存，请检查邮箱以确认新地址。',
    'Profile saved, but email change failed:': '个人资料已保存，但电子邮箱修改失败：',
    'Smart Reminders': '智能提醒',
    'Morning Commute (7:30 AM)': '早晨通勤（上午 7:30）',
    'Evening Return (6:00 PM)': '傍晚返程（下午 6:00）',
    'Save & Close': '保存并关闭',
    'Travel History': '出行记录',
    'Daily Commute Settings': '日常通勤设置',
    'Favourite Routes': '常用路线',
    'Sign Out': '退出登录',
    'Language': '语言',
    'App Language': '应用语言',
    'English': 'English',
    'Chinese': '中文',
    'Malay': 'Bahasa Melayu',
    'Trips Taken': '完成旅程',
    'Saved Routes': '已存路线',
    'Active Alerts': '启用提醒',
    'Viewing recent trips...': '正在查看最近的旅程……',
    'ROUTE OPTIMIZATION': '路线优化',
    'Journey Planning': '旅程规划',
    'ROAD SEARCH': '路线搜索',
    'Select Starting Point': '选择起点',
    'Select Destination': '选择终点',
    'Search station...': '搜索车站……',
    'Select starting point': '选择起点',
    'Select destination': '选择终点',
    'Find Routes': '查找路线',
    'ROUTE COMPARISON': '路线比较',
    'JOURNEY SUMMARY': '旅程摘要',
    'Recommended Route': '推荐路线',
    'DEPART': '出发',
    'ARRIVE': '抵达',
    'DURATION': '时长',
    'ESTIMATED FARE': '预计车费',
    'WALK TO STATION': '步行至车站',
    'Start Journey': '开始旅程',
    '✓ Journey Confirmed': '✓ 旅程已确认',
    'AI Crowd Intelligence': 'AI 人流分析',
    'Crowd Estimate': '人流预测',
    'Peak Hours': '高峰时段',
    'History': '历史记录',
    'Station Crowd Estimate': '车站人流预测',
    'Station': '车站',
    'Day': '日期',
    'Time': '时间',
    'Predict Crowd': '预测人流',
    'Loading station data...': '正在载入车站数据……',
    'EXPECTED CROWD': '预计人流',
    'EST. QUEUE': '预计排队',
    'Peak Hour Pattern': '高峰时段趋势',
    'Show Peak Pattern': '显示高峰趋势',
    'Ridership History': '乘客量历史',
    'Load History': '载入历史记录',
    'No records found for this station in the local dataset.':
        '本地数据集中找不到此车站的记录。',
    'AVERAGE': '平均',
    'HIGHEST': '最高',
    'LOWEST': '最低',
    'Daily totals': '每日总数',
    'Monday': '星期一',
    'Tuesday': '星期二',
    'Wednesday': '星期三',
    'Thursday': '星期四',
    'Friday': '星期五',
    'Saturday': '星期六',
    'Sunday': '星期日',
    'LOW': '低',
    'MODERATE': '中等',
    'HIGH': '高',
    'CRITICAL': '严重',
  },
  'ms': {
    'Journey': 'Perjalanan',
    'Stations': 'Stesen',
    'AI Crowd': 'AI Kesesakan',
    'Profile': 'Profil',
    'Analytics': 'Analitik',
    'Transport Data': 'Data Pengangkutan',
    'Analytics Centre': 'Pusat Analitik',
    'coming soon': 'akan datang',
    'Create Account': 'Cipta Akaun',
    'Welcome Back': 'Selamat Kembali',
    'Create your NextRoute account': 'Cipta akaun NextRoute anda',
    'Sign in to continue to NextRoute': 'Log masuk untuk meneruskan ke NextRoute',
    'Display name': 'Nama paparan',
    'Email': 'E-mel',
    'Password': 'Kata laluan',
    'Register': 'Daftar',
    'Sign In': 'Log Masuk',
    'Already have an account? Sign In': 'Sudah mempunyai akaun? Log masuk',
    'New user? Create an account': 'Pengguna baharu? Cipta akaun',
    'Verify your email': 'Sahkan E-mel Anda',
    'Enter the 8-digit code sent to':
        'Masukkan kod 8 digit yang dihantar kepada',
    'Verification code': 'Kod pengesahan',
    'Verify Code': 'Sahkan Kod',
    'Resend Code': 'Hantar Semula Kod',
    'Resend code in': 'Hantar semula dalam',
    'Change email address': 'Tukar alamat e-mel',
    'Please enter the 8-digit verification code.':
        'Sila masukkan kod pengesahan 8 digit.',
    'Verification code resent.': 'Kod pengesahan telah dihantar semula.',
    'Email verified successfully.': 'E-mel berjaya disahkan.',
    'Confirm new email': 'Sahkan E-mel Baharu',
    'Enter the 8-digit code sent to your new email':
        'Masukkan kod 8 digit yang dihantar ke e-mel baharu anda',
    'Turn off Secure email change in Supabase, then request a new code.':
        'Matikan Secure email change dalam Supabase, kemudian minta kod baharu.',
    'Email change is still pending. Confirm the message sent to your old email or disable Secure email change.':
        'Perubahan e-mel masih belum selesai. Sahkan mesej yang dihantar ke e-mel lama atau matikan Secure email change.',
    'Please enter your name.': 'Sila masukkan nama anda.',
    'Please enter a valid email address.': 'Sila masukkan alamat e-mel yang sah.',
    'Password must contain at least 6 characters.':
        'Kata laluan mesti mengandungi sekurang-kurangnya 6 aksara.',
    'Account created. Please confirm your email.':
        'Akaun telah dicipta. Sila sahkan e-mel anda.',
    'Account created successfully.': 'Akaun berjaya dicipta.',
    'Signed in successfully.': 'Berjaya log masuk.',
    'Something went wrong. Please try again.': 'Ralat berlaku. Sila cuba lagi.',
    'My Profile': 'Profil Saya',
    'Edit Profile': 'Edit Profil',
    'Member ID': 'ID Ahli',
    'Your unique member ID cannot be changed.': 'ID ahli unik anda tidak boleh diubah.',
    'Location': 'Lokasi',
    'Phone number': 'Nombor telefon',
    'Cancel': 'Batal',
    'Save': 'Simpan',
    'Display name cannot be empty.': 'Nama paparan tidak boleh kosong.',
    'Display name must be 50 characters or fewer.':
        'Nama paparan mestilah 50 aksara atau kurang.',
    'Location must be 100 characters or fewer.':
        'Lokasi mestilah 100 aksara atau kurang.',
    'Use 10–11 digits starting with 01.':
        'Gunakan 10–11 digit yang bermula dengan 01.',
    'Unable to load profile.': 'Profil tidak dapat dimuatkan.',
    'Unable to update profile.': 'Profil tidak dapat dikemas kini.',
    'Profile updated successfully.': 'Profil berjaya dikemas kini.',
    'Profile saved. Check your email to confirm the new address.':
        'Profil disimpan. Semak e-mel untuk mengesahkan alamat baharu.',
    'Profile saved, but email change failed:':
        'Profil disimpan, tetapi perubahan e-mel gagal:',
    'Smart Reminders': 'Peringatan Pintar',
    'Morning Commute (7:30 AM)': 'Perjalanan Pagi (7:30 PG)',
    'Evening Return (6:00 PM)': 'Perjalanan Balik Petang (6:00 PTG)',
    'Save & Close': 'Simpan & Tutup',
    'Travel History': 'Sejarah Perjalanan',
    'Daily Commute Settings': 'Tetapan Perjalanan Harian',
    'Favourite Routes': 'Laluan Kegemaran',
    'Sign Out': 'Log Keluar',
    'Language': 'Bahasa',
    'App Language': 'Bahasa Aplikasi',
    'English': 'English',
    'Chinese': '中文',
    'Malay': 'Bahasa Melayu',
    'Trips Taken': 'Perjalanan',
    'Saved Routes': 'Laluan Disimpan',
    'Active Alerts': 'Amaran Aktif',
    'Viewing recent trips...': 'Melihat perjalanan terkini...',
    'ROUTE OPTIMIZATION': 'PENGOPTIMUMAN LALUAN',
    'Journey Planning': 'Perancangan Perjalanan',
    'ROAD SEARCH': 'CARIAN LALUAN',
    'Select Starting Point': 'Pilih Tempat Mula',
    'Select Destination': 'Pilih Destinasi',
    'Search station...': 'Cari stesen...',
    'Select starting point': 'Pilih tempat mula',
    'Select destination': 'Pilih destinasi',
    'Find Routes': 'Cari Laluan',
    'ROUTE COMPARISON': 'PERBANDINGAN LALUAN',
    'JOURNEY SUMMARY': 'RINGKASAN PERJALANAN',
    'Recommended Route': 'Laluan Disyorkan',
    'DEPART': 'BERTOLAK',
    'ARRIVE': 'TIBA',
    'DURATION': 'TEMPOH',
    'ESTIMATED FARE': 'ANGGARAN TAMBANG',
    'WALK TO STATION': 'BERJALAN KE STESEN',
    'Start Journey': 'Mulakan Perjalanan',
    '✓ Journey Confirmed': '✓ Perjalanan Disahkan',
    'AI Crowd Intelligence': 'Kecerdasan Kesesakan AI',
    'Crowd Estimate': 'Anggaran Kesesakan',
    'Peak Hours': 'Waktu Puncak',
    'History': 'Sejarah',
    'Station Crowd Estimate': 'Anggaran Kesesakan Stesen',
    'Station': 'Stesen',
    'Day': 'Hari',
    'Time': 'Masa',
    'Predict Crowd': 'Ramalkan Kesesakan',
    'Loading station data...': 'Memuatkan data stesen...',
    'EXPECTED CROWD': 'JANGKAAN KESESAKAN',
    'EST. QUEUE': 'ANGGARAN BARISAN',
    'Peak Hour Pattern': 'Corak Waktu Puncak',
    'Show Peak Pattern': 'Tunjukkan Corak Puncak',
    'Ridership History': 'Sejarah Penumpang',
    'Load History': 'Muatkan Sejarah',
    'No records found for this station in the local dataset.':
        'Tiada rekod ditemui untuk stesen ini dalam set data tempatan.',
    'AVERAGE': 'PURATA',
    'HIGHEST': 'TERTINGGI',
    'LOWEST': 'TERENDAH',
    'Daily totals': 'Jumlah harian',
    'Monday': 'Isnin',
    'Tuesday': 'Selasa',
    'Wednesday': 'Rabu',
    'Thursday': 'Khamis',
    'Friday': 'Jumaat',
    'Saturday': 'Sabtu',
    'Sunday': 'Ahad',
    'LOW': 'RENDAH',
    'MODERATE': 'SEDERHANA',
    'HIGH': 'TINGGI',
    'CRITICAL': 'KRITIKAL',
  },
};
