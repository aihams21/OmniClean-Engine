// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'أومني كلين إنجن';

  @override
  String get navDashboard => 'لوحة التحكم';

  @override
  String get navCleaner => 'المنظّف';

  @override
  String get navDuplicates => 'المكرّرات';

  @override
  String get navQuarantine => 'العزل';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get actionCancel => 'إلغاء';

  @override
  String get actionClose => 'إغلاق';

  @override
  String get actionConfirm => 'تأكيد';

  @override
  String get actionContinue => 'متابعة';

  @override
  String get actionRestore => 'استعادة';

  @override
  String get actionPurge => 'حذف نهائي';

  @override
  String get actionOk => 'حسنًا';

  @override
  String get dashboardTitle => 'مركز القيادة';

  @override
  String get dashboardSubtitle => 'صحة الجهاز الآن، وكل ما يمكن استرجاعه منه.';

  @override
  String get dashboardReclaimable => 'قابل للاسترداد الآن';

  @override
  String get dashboardHeldBack => 'محجوز لتطبيقات قيد التشغيل';

  @override
  String get dashboardScanAll => 'افحص كل شيء';

  @override
  String get dashboardCleanSelected => 'نظّف المحدد';

  @override
  String get dashboardNothingScanned =>
      'ما في فحص بعد. ابدأ فحص لتعرف شو ممكن يسترجع هذا الجهاز.';

  @override
  String dashboardScanDuration(Object seconds) {
    return 'خلص الفحص بـ $seconds ثانية';
  }

  @override
  String get dashboardCancelled => 'تم إلغاء الفحص — النتائج ناقصة';

  @override
  String dashboardFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف',
      many: '$count ملفًا',
      few: '$count ملفات',
      two: 'ملفّين',
      one: 'ملف واحد',
      zero: 'ما في ملفات',
    );
    return '$_temp0';
  }

  @override
  String get dashboardActivityLog => 'سجل النشاط';

  @override
  String get dashboardLogEmpty => 'ما في شي مسجّل بعد.';

  @override
  String get dashboardLoadAverage => 'متوسط الحِمل';

  @override
  String get dashboardUptime => 'مدة التشغيل';

  @override
  String dashboardCores(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نواة',
      many: '$count نواة',
      few: '$count أنوية',
      two: 'نواتين',
      one: 'نواة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get dashboardStorage => 'التخزين';

  @override
  String dashboardStorageFree(String bytes, String total) {
    return '$bytes متاح من $total';
  }

  @override
  String dashboardMoreDisks(int count) {
    return 'و$count غيرها';
  }

  @override
  String get gaugeCpu => 'المعالج';

  @override
  String get gaugeMemory => 'الذاكرة';

  @override
  String get gaugeSwap => 'الذاكرة الافتراضية';

  @override
  String get unavailable => 'غير متاح';

  @override
  String get cleanerTitle => 'المنظّف';

  @override
  String get cleanerSubtitle =>
      'مافي شي بينحذف هون. كل شي بينتقل إلى العزل ويضل قابل للاسترجاع.';

  @override
  String get cleanerScanAll => 'افحص كل الوحدات';

  @override
  String get cleanerRescan => 'إعادة فحص';

  @override
  String get cleanerCleanSelected => 'نظّف المحدد';

  @override
  String get cleanerSelectAll => 'تحديد الكل';

  @override
  String get cleanerSelectNone => 'إلغاء التحديد';

  @override
  String get cleanerNothingFound => 'ما في شي لتنظيفه بهالوحدة.';

  @override
  String get cleanerNothingScanned => 'شغّل فحص أول شي عشان تقيس كل وحدة.';

  @override
  String get cleanerRequiresRoot => 'يحتاج صلاحيات مدير';

  @override
  String get cleanerRootPrompt =>
      'أومني كلين يحتاج صلاحيات مدير ينظّف كاش النظام.';

  @override
  String get cleanerIdling => 'خامل';

  @override
  String get cleanerScanning => 'عم يفحص…';

  @override
  String get cleanerCleaning => 'عم ينظّف…';

  @override
  String get cleanerDone => 'خلص';

  @override
  String get cleanerFailed => 'فشل';

  @override
  String get riskSafe => 'آمن';

  @override
  String get riskModerate => 'متوسط';

  @override
  String get riskElevated => 'مرتفع';

  @override
  String get cleanerConfirmTitle => 'ننقل للعزل؟';

  @override
  String cleanerConfirmBody(int files, String bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files ملف',
      many: '$files ملفًا',
      few: '$files ملفات',
      two: 'ملفّين',
      one: 'ملف واحد',
    );
    return '$_temp0 · $bytes راح تنتقل للعزل. تقدر ترجّع كل عنصر من شاشة العزل.';
  }

  @override
  String get cleanerConfirmProceed => 'انقل إلى العزل';

  @override
  String cleanerResultBody(String bytes, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files ملف',
      many: '$files ملفًا',
      few: '$files ملفات',
      two: 'ملفّين',
      one: 'ملف واحد',
    );
    return 'استرجعنا $bytes من $_temp0.';
  }

  @override
  String cleanerSkippedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر انحجز',
      many: '$count عنصرًا انحجز',
      few: '$count عناصر انحجزت',
      two: 'عنصرين انحجزوا',
      one: 'عنصر واحد انحجز',
    );
    return '$_temp0 بسبب بوابة الأمان.';
  }

  @override
  String cleanerProgress(int done, int total) {
    return '$done من $total';
  }

  @override
  String cleanerHeldBack(String bytes) {
    return '$bytes محجوز (لسا مستخدم)';
  }

  @override
  String get duplicatesTitle => 'باحث المكرّرات';

  @override
  String get duplicatesSubtitle =>
      'يقارن المحتوى، مو الأسماء. كل ملف بينتحقّق بخوارزمية SHA-256.';

  @override
  String get duplicatesRoots => 'المجلدات المراد فحصها';

  @override
  String get duplicatesRootHint => '/home/you/Downloads';

  @override
  String get duplicatesAddRoot => 'أضف مجلد';

  @override
  String get duplicatesRemoveRoot => 'احذف';

  @override
  String get duplicatesNoRoots => 'أضف مجلد واحد على الأقل حتى تفحص.';

  @override
  String get duplicatesFind => 'دوّر على المكرّرات';

  @override
  String get duplicatesCancelScan => 'أوقف الفحص';

  @override
  String get duplicatesPhaseWalking => 'عم يمشي على المجلدات…';

  @override
  String get duplicatesPhasePreFiltering => 'عم يقارن الأحجام…';

  @override
  String get duplicatesPhaseHashing => 'عم يحسب البصمات…';

  @override
  String get duplicatesPhaseDone => 'خلص';

  @override
  String duplicatesSummary(int groups, String bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups مجموعة',
      many: '$groups مجموعة',
      few: '$groups مجموعات',
      two: 'مجموعتين',
      one: 'مجموعة وحدة',
      zero: 'ما في مجموعات مكرّرة',
    );
    return '$_temp0 · $bytes مهدور';
  }

  @override
  String duplicatesCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نسخة',
      many: '$count نسخة',
      few: '$count نسخ',
      two: 'نسختين',
      one: 'نسخة وحدة',
    );
    return '$_temp0';
  }

  @override
  String get duplicatesKeep => 'احتفظ';

  @override
  String get duplicatesCopiesLabel => 'النسخ اللي بدنا نحتفظ فيها';

  @override
  String get duplicatesDeleteDuplicates => 'احذف الباقي';

  @override
  String duplicatesSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف محدد',
      many: '$count ملفًا محددًا',
      few: '$count ملفات محددة',
      two: 'ملفّين محددين',
      one: 'ملف واحد محدد',
      zero: 'ما حديد شي',
    );
    return '$_temp0';
  }

  @override
  String duplicatesConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نسخة',
      many: '$count نسخة',
      few: '$count نسخ',
      two: 'نسختين',
      one: 'نسخة وحدة',
    );
    return 'نحذف $_temp0؟';
  }

  @override
  String get duplicatesConfirmBody =>
      'النسخة اللي حافظت عليها ما بينمسّها شي. الباقي بيننقل للعزل وتقدر ترجّعه بأي وقت.';

  @override
  String get duplicatesSuggested => 'النسخة المقترحة';

  @override
  String duplicatesHashPrefix(String prefix) {
    return 'SHA-256 $prefix…';
  }

  @override
  String get quarantineTitle => 'العزل';

  @override
  String get quarantineSubtitle =>
      'ما في شي بيدمّره أومني كلين. كل شي بيستنى هون لحد ما ترجّعه أو تحذفه نهائيًا.';

  @override
  String get quarantineEmpty => 'العزل فاضي.';

  @override
  String quarantineHolding(String bytes) {
    return 'محتار $bytes';
  }

  @override
  String quarantineItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصرين',
      one: 'عنصر واحد',
      zero: 'ما في عناصر',
    );
    return '$_temp0';
  }

  @override
  String quarantineFrom(String module) {
    return 'من $module';
  }

  @override
  String quarantineWhen(String when) {
    return 'انتقل للعزل $when';
  }

  @override
  String get quarantineRestoreOne => 'تم استرجاع العنصر.';

  @override
  String get quarantinePurgeOne => 'تم حذف العنصر نهائيًا.';

  @override
  String get quarantinePurgeTitle => 'حذف نهائي؟';

  @override
  String quarantinePurgeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر بالعزل',
      many: '$count عنصرًا بالعزل',
      few: '$count عناصر بالعزل',
      two: 'عنصرين بالعزل',
      one: 'عنصر واحد بالعزل',
    );
    return '$_temp0 راح ينحذفوا للأبد. هالشي ما بيرجع.';
  }

  @override
  String get quarantinePurgeAll => 'احذف كل شي';

  @override
  String quarantineExpiredNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر طعّى مدته',
      many: '$count عنصرًا طعّى مدته',
      few: '$count عناصر طعوا مدتهم',
      two: 'عنصرين طعوا مدتهم',
      one: 'عنصر واحد طعّى مدته',
      zero: 'ما في شي طعّى مدته',
    );
    return '$_temp0';
  }

  @override
  String quarantineRetention(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يوم',
      many: '$days يومًا',
      few: '$days أيام',
      two: 'يومين',
      one: 'يوم',
    );
    return 'مدة الاستعادة: $_temp0';
  }

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get settingsAccent => 'لون الهوية';

  @override
  String get themeCyber => 'أخضر سيبراني';

  @override
  String get themeCrimson => 'قرمزي عميق';

  @override
  String get themeCyberHint => 'إشارة خضراء. طرفيّة كلاسيكية.';

  @override
  String get themeCrimsonHint => 'إنذار أحمر. للعناصر الصاخبة.';

  @override
  String get settingsLanguageSection => 'اللغة';

  @override
  String get settingsLanguage => 'لغة التطبيق';

  @override
  String get langSystem => 'حسب نظام الجهاز';

  @override
  String get langEnglish => 'English';

  @override
  String get langArabic => 'العربية';

  @override
  String get settingsSafety => 'الأمان';

  @override
  String get settingsMinAge => 'أقدم عمر للملف';

  @override
  String settingsMinAgeValue(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ساعة',
      many: '$hours ساعة',
      few: '$hours ساعات',
      two: 'ساعتين',
      one: 'ساعة',
    );
    return '$_temp0';
  }

  @override
  String get settingsMinAgeHint =>
      'الملفات اللي انمسكت من قريب ما بينمسّها شي — يمكن تطبيق شغّال لسا محتاجها.';

  @override
  String get settingsRetention => 'مدة الاستعادة';

  @override
  String get settingsRetentionHint =>
      'العناصر اللي عدّت هالمدة بينعرضوا للحذف النهائي.';

  @override
  String get settingsQuarantinePath => 'مكان العزل';

  @override
  String get settingsDiagnostics => 'التشخيص';

  @override
  String get settingsRootAccess => 'صلاحية المدير';

  @override
  String get rootAvailable => 'متاحة';

  @override
  String get rootUnavailable => 'غير متاحة';

  @override
  String get rootUnavailableHint =>
      'وحدات النظام راح تبلّغ إنها محتاجة صلاحيات.';

  @override
  String get settingsOpenLog => 'سجل النشاط';

  @override
  String get settingsAbout => 'عن التطبيق';

  @override
  String get aboutHeadline => 'منظّف متعدد المنصات ما بيقدر يكذب عليك.';

  @override
  String get aboutBody =>
      'أومني كلين ما بيحذف أي ملف بشكل مباشر. كل شي بيجمعه بينتقل لعزل إنت بتحكم فيه، وقائمة منع صارمة بتمنع مسارات النظام والمفاتيح وقواعد البيانات قبل ما حتى تُقرأ أول بايت.';

  @override
  String versionLabel(String version, String build) {
    return 'الإصدار $version ($build)';
  }

  @override
  String get settingsReset => 'رجّع للإعدادات الافتراضية';

  @override
  String get settingsResetDone => 'رجّعنا الإعدادات.';

  @override
  String platformLabel(String platform) {
    return 'المنصة المكتشفة: $platform';
  }

  @override
  String get riskWhyElevated => 'بيلمس ملفات يملكها النظام. لازم تشغّله كمدير.';

  @override
  String get riskWhyModerate =>
      'بيحذف ملفات يمكن تطبيق شغّال لسا يعيد إنشاءها.';

  @override
  String get riskWhySafe => 'كاشات وتخزين مؤقت بيرجعوا لحالهم بس.';

  @override
  String errorGeneric(String message) {
    return 'صار خطأ: $message';
  }

  @override
  String get targetAptArchiveTitle => 'أرشيف حزم APT';

  @override
  String get targetAptArchiveDescription =>
      'ملفات .deb المحمّلة للتبثيت من جديد';

  @override
  String get targetAptListsTitle => 'فهارس حزم APT';

  @override
  String get targetAptListsDescription => 'القوائم التي يحدّثها apt من الشبكة';

  @override
  String get targetJournalTitle => 'سجل النظام';

  @override
  String get targetJournalDescription => 'سجلات systemd لكل الجهاز';

  @override
  String get targetCrashReportsTitle => 'تقارير الأعطال';

  @override
  String get targetCrashReportsDescription => 'تفريغات الأعطال المحفوظة';

  @override
  String get targetTmpTitle => 'ملفات مؤقتة';

  @override
  String get targetTmpDescription => 'ما تبقّى في مجلّدات الملفات المؤقتة';

  @override
  String get targetHomeCacheTitle => 'ذاكرة المستخدم المؤقتة';

  @override
  String get targetHomeCacheDescription => 'مجلّد الذاكرة المؤقتة لهذا الحساب';

  @override
  String get targetUserJournalTitle => 'سجل المستخدم';

  @override
  String get targetUserJournalDescription => 'سجلّات تخصّ حسابك وحده';

  @override
  String get targetTrashTitle => 'سلة المحذوفات';

  @override
  String get targetTrashDescription => 'ملفات محذوفة ما زالت بالسلة';

  @override
  String get targetFlatpakCacheTitle => 'ذاكرة فلاتpak';

  @override
  String get targetFlatpakCacheDescription =>
      'الحزم المنزّلة والملفات المتبقّية';

  @override
  String get targetThumbnailsTitle => 'الصور المصغّرة';

  @override
  String get targetThumbnailsDescription => 'معاينات لصور عندك أصلاً';

  @override
  String get targetUserTempTitle => 'ملفات المستخدم المؤقتة';

  @override
  String get targetUserTempDescription => 'مجلّد الملفات المؤقتة لحسابك';

  @override
  String get targetWindowsTempTitle => 'ملفات ويندوز المؤقتة';

  @override
  String get targetWindowsTempDescription => 'مجلّد ويندوز المؤقت';

  @override
  String get targetEdgeCacheTitle => 'ذاكرة Edge';

  @override
  String get targetEdgeCacheDescription => 'بيانات تصفّح يمكن بناؤها من جديد';

  @override
  String get targetChromeCacheTitle => 'ذاكرة كروم';

  @override
  String get targetChromeCacheDescription => 'بيانات تصفّح يمكن بناؤها من جديد';

  @override
  String get targetFirefoxCacheTitle => 'ذاكرة فايرفوكس';

  @override
  String get targetFirefoxCacheDescription => 'ذاكرة الملفات للملفات الشخصية';

  @override
  String get targetEventLogsTitle => 'سجلّات الأحداث';

  @override
  String get targetEventLogsDescription => 'أرشيف سجلّات أحداث ويندوز';

  @override
  String get targetErrorReportingTitle => 'تقارير الأخطاء';

  @override
  String get targetErrorReportingDescription =>
      'ملفات بانتظار تقرير أخطاء ويندوز';

  @override
  String get targetMinidumpsTitle => 'تفريغات الذاكرة الصغيرة';

  @override
  String get targetMinidumpsDescription => 'تفريغات ما بعد الشاشة الزرقاء';

  @override
  String get targetUpdateDownloadTitle => 'تحميلات تحديث ويندوز';

  @override
  String get targetUpdateDownloadDescription => 'حزم تنزيل بانتظار التثبيت';

  @override
  String get targetDeliveryOptimizationTitle => 'تحسين التسليم';

  @override
  String get targetDeliveryOptimizationDescription =>
      'ذاكرة تحديث مشاركة الأقران';

  @override
  String get targetInstallerPendingTitle => 'تثبيتات معلّقة';

  @override
  String get targetInstallerPendingDescription =>
      'أعمال تثبيت تنتظر إعادة التشغيل';

  @override
  String get targetSetupLogsTitle => 'سجلّات التثبيت';

  @override
  String get targetSetupLogsDescription => 'سجلّات آخر عملية تثبيت لويندوز';

  @override
  String get targetAppCacheRootTitle => 'ذاكرة كل التطبيقات';

  @override
  String get targetAppCacheRootDescription => 'ذاكرة كل التطبيقات المثبّتة';

  @override
  String get targetAppCacheSelfTitle => 'ذاكرة OmniClean';

  @override
  String get targetAppCacheSelfDescription => 'الملفات المؤقتة لهذا التطبيق';

  @override
  String get targetDownloadsJunkTitle => 'ملفات تنزيل فوضوية';

  @override
  String get targetDownloadsJunkDescription => 'تنزيلات متوقّفة ومثبّات قديمة';

  @override
  String get targetObbLeftoversTitle => 'ملفات توسيع قديمة';

  @override
  String get targetObbLeftoversDescription => 'حزم تطبيق أزلته';

  @override
  String get targetMediaThumbnailsTitle => 'معاينات الوسائط';

  @override
  String get targetMediaThumbnailsDescription => 'معاينات الصور والفيديو';

  @override
  String get navLibrary => 'المكتبة';

  @override
  String get libraryTitle => 'المكتبة';

  @override
  String get librarySubtitle =>
      'كل صورة وفيديو وملف على الجهاز — مرتّب من الأحدث للأقدم.';

  @override
  String get libraryLoad => 'حمّل';

  @override
  String get libraryReloading => 'عم يحمّل…';

  @override
  String get libraryKindPhotos => 'الصور';

  @override
  String get libraryKindVideos => 'الفيديوهات';

  @override
  String get libraryKindAudio => 'الصوتيات';

  @override
  String get libraryKindDocuments => 'المستندات';

  @override
  String get libraryKindDownloads => 'التحميلات';

  @override
  String get libraryKindAllFiles => 'كل الملفات';

  @override
  String get libraryEmpty => 'ما في شي هون.';

  @override
  String get libraryBlind => 'لازم صلاحية الوصول للتخزين';

  @override
  String get libraryBlindHint =>
      'أومني كلين محتاج صلاحية يقرأ صورك وملفاتك. ما في شي بينرفع عالنت — الفحص كله على الجهاز.';

  @override
  String get libraryGrant => 'اسمح بالوصول';

  @override
  String libraryCount(int count, String size) {
    return '$count عنصر · $size';
  }

  @override
  String libraryResolution(int width, int height) {
    return '$width x $height';
  }

  @override
  String get libraryFailed => 'ما قدرنا نقرأ مكتبة الجهاز.';

  @override
  String get libraryUseDuplicates => 'دور على المكررات';

  @override
  String get navApps => 'التطبيقات';

  @override
  String get unusedAppsTitle => 'تطبيقات ما بتستخدمها';

  @override
  String get unusedAppsSubtitle =>
      'تطبيقات توقّف تفتحها، ومعها كل شي خلّفته ورا.';

  @override
  String get unusedAppsLoad => 'افحص تطبيقاتي';

  @override
  String get unusedAppsRefreshing => 'عم أقرا بيانات الاستخدام…';

  @override
  String get unusedAppsIdle =>
      'لسّا ما فحصنا شي. اضغط الزر فوق و OmniClean رح يسأل النظام أي تطبيقات توقّفت تستخدمها.';

  @override
  String get unusedAppsEmpty =>
      'ما في تطبيقات مهملة بهالحد. ارفع الحد عشان تبعد أكتر بالماضي.';

  @override
  String unusedAppsCount(Object count, Object size) {
    return '$count تطبيق · $size';
  }

  @override
  String get unusedAppsNeverOpened => 'ما انفتح أبداً';

  @override
  String unusedAppsIdleDays(Object days) {
    return '$days يوم بدون استخدام';
  }

  @override
  String get unusedAppsUninstall => 'إلغاء التثبيت';

  @override
  String get unusedAppsUninstalling => 'عم فتح إلغاء التثبيت بتاع النظام…';

  @override
  String unusedAppsUninstalled(Object name) {
    return '$name انبعتت لإلغاء التثبيت بتاع النظام.';
  }

  @override
  String get unusedAppsBlind =>
      'لازم صلاحية الوصول لبيانات الاستخدام. أندرويد ما بيعرف أي تطبيقات توقّفت تستخدمها إلا إذا سمحت له يراقب إحصائيات الاستخدام.';

  @override
  String get unusedAppsGrant => 'اسمح بالوصول للاستخدام';

  @override
  String get unusedAppsSystemHidden => 'تطبيقات النظام ما بنقترح حذفها أبداً.';

  @override
  String get unusedAppsCannotUninstall =>
      'هذا الجهاز ما يسمح لأي تطبيق يمسح تطبيقات تانية.';

  @override
  String get unusedAppsThreshold => 'بدون استخدام منذ';

  @override
  String unusedAppsSelected(Object count, Object size) {
    return '$count محدد · $size';
  }

  @override
  String get unusedAppsRemoveSelected => 'ألغِ المحدد';

  @override
  String unusedAppsConfirmTitle(Object count) {
    return 'ألغِ تثبيت $count تطبيق؟';
  }

  @override
  String get unusedAppsConfirmBody =>
      'إلغاء التثبيت بيفتح تطبيق واحد كل مرة وأنت بتأكد. OmniClean ما بيحذف بيانات التطبيق أبداً.';

  @override
  String get unusedAppsFailed =>
      'ما قدرنا نقرأ قائمة التطبيقات. جرّب كمان مرّة.';

  @override
  String get navBoost => 'تسريع';

  @override
  String get boostTitle => 'تسريع';

  @override
  String get boostSubtitle =>
      'كبسة وحدة. تغييرات حقيقية على النظام، وكل خطوة بتقل لك شو عملت بالظبط.';

  @override
  String get boostRun => 'سرّع الآن';

  @override
  String get boostRunning => 'عم يسرّع…';

  @override
  String get boostRerun => 'سرّع كمان مرّة';

  @override
  String get boostNothingAvailable =>
      'التسريع بده صلاحيات مدير على هالمنصّة، فما في شي هون يقدر يوعدك فيه.';

  @override
  String boostResultHeadline(int done, int total) {
    return 'طبّقت $done من $total خطوة';
  }

  @override
  String get boostNothingChanged =>
      'ما تغيّر شي. كل خطوة تحت هي اللي النظام رفضها.';

  @override
  String get boostActionAndroidTitle => 'تقليم وتنضيف النظام كله';

  @override
  String get boostActionAndroidDescription =>
      'يطلب من أندرويد يحرّر كاشات التطبيقات، ويقلّم ذاكرة هالتطبيق، وبيشيل تقييد doze ليبقى المشغّل سريع.';

  @override
  String get boostActionPowerPlanTitle => 'تبديل على خطة أداء عالي';

  @override
  String get boostActionPowerPlanDescription =>
      'بيمنع ويندوز من نزول تردد المعالج والكرت للتوفير وأنا شغال.';

  @override
  String get boostActionWorkingSetsTitle => 'تحرير الذاكرة الخاملة من كل تطبيق';

  @override
  String get boostActionWorkingSetsDescription =>
      'يطلب من كل عملية ترجّع الصفحات اللي محتجزة وما عم تستعملها، وهي اللي بتربع اللعب.';

  @override
  String get boostActionIndexerTitle => 'إيقاف مفهرس البحث';

  @override
  String get boostActionIndexerDescription =>
      'مفهرس البحث بيعيد الفحص للخلفية وياكل نفس الديسك والمعالج اللي اللعبة بدها.';

  @override
  String get boostActionGovernorTitle => 'تثبيت المعالج على وضع الأداء';

  @override
  String get boostActionGovernorDescription =>
      'بيبدّلGovernor توفير الطاقة لتضل الأنوية على أقوى تردد بدل ما تنزل وتطلع طول اللعب.';

  @override
  String get boostActionSwappinessTitle => 'منع النواة من التبديل';

  @override
  String get boostActionSwappinessDescription =>
      'تخفيض swappiness بيخلي النواة تستعمل الرام الفاضي بدل الديسك البطيء، ومن هناك بييجي تقطيع الإطارات.';

  @override
  String get boostActionDropCachesTitle => 'تحرير ذاكرة الكاش للنواة';

  @override
  String get boostActionDropCachesDescription =>
      'بيحرّر صفحات الملفات المخزّنة، فتصير الكاش فاضية وكل قراءة بعدها قراءة حقيقية.';

  @override
  String get boostActionTrimTitle => 'تنظيف القرص الصلب SSD';

  @override
  String get boostActionTrimDescription =>
      'بيبلّغ القرص إنو بلوكات صارت محذوفة، فبيوقف ترتيب كتابات فوقها.';

  @override
  String get boostImpactFrames => 'معدّل الإطارات';

  @override
  String get boostImpactMemory => 'الذاكرة';

  @override
  String get boostImpactLatency => 'استجابة القرص';

  @override
  String get boostImpactStorage => 'التخزين';

  @override
  String get boostRequiresPrivilege => 'صلاحيات مدير';
}
