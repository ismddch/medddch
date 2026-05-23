import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('سياسة الخصوصية',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سياسة الخصوصية لتطبيق حلاقك',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'آخر تحديث: مايو 2026',
              style: GoogleFonts.cairo(
                  fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),
            const _Section(
              title: '1. المعلومات التي نجمعها',
              body:
                  'نجمع المعلومات التي تقدمها مباشرةً عند إنشاء حساب، مثل الاسم ورقم الهاتف. كما نجمع الصور التي ترفعها (صورة الملف الشخصي، صور الأعمال، إيصالات الدفع) وبيانات استخدام التطبيق كمعلومات الطابور وسجل الحجوزات.',
            ),
            const _Section(
              title: '2. كيفية استخدام المعلومات',
              body:
                  'نستخدم معلوماتك لتشغيل خدمة الحجز وإدارة الطابور، وإرسال إشعارات تتعلق بحجزك، وعرض ملفك الشخصي لمزود الخدمة المختار، وتحسين تجربة التطبيق.',
            ),
            const _Section(
              title: '3. مشاركة المعلومات',
              body:
                  'لا نبيع بياناتك الشخصية لأطراف ثالثة. نشارك بياناتك فقط مع مزودي الخدمة المختارين (الحلاقين وأصحاب الصالونات) بالقدر اللازم لإتمام الحجز، ومع مزودي الخدمات التقنية (Supabase، Firebase) لتشغيل التطبيق.',
            ),
            const _Section(
              title: '4. تخزين البيانات وأمانها',
              body:
                  'تُخزَّن بياناتك على خوادم آمنة مشفّرة. نتخذ إجراءات تقنية وتنظيمية معقولة لحماية معلوماتك من الوصول غير المصرح به أو الإفصاح عنها.',
            ),
            const _Section(
              title: '5. الصور والوسائط',
              body:
                  'الصور التي ترفعها (صورة الملف الشخصي، صور الأعمال، إيصالات الدفع) تُخزَّن على خوادمنا وتُستخدَم فقط لأغراض التطبيق. لا نشارك صورك مع أطراف غير معنية بالخدمة.',
            ),
            const _Section(
              title: '6. الإشعارات',
              body:
                  'يستخدم التطبيق إشعارات Push لإعلامك بحالة حجزك وتحديثات الطابور. يمكنك إدارة الإشعارات من إعدادات جهازك.',
            ),
            const _Section(
              title: '7. حقوقك',
              body:
                  'يحق لك الوصول إلى بياناتك الشخصية وتصحيحها أو حذف حسابك في أي وقت من داخل التطبيق. للاستفسارات المتعلقة بخصوصيتك، تواصل معنا عبر واتساب من خلال زر الدعم في صفحة تسجيل الدخول.',
            ),
            const _Section(
              title: '8. التغييرات على هذه السياسة',
              body:
                  'قد نُحدِّث سياسة الخصوصية هذه من وقت لآخر. سنُعلمك بأي تغييرات جوهرية عبر إشعار داخل التطبيق.',
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'باستخدامك لتطبيق حلاقك، فإنك توافق على سياسة الخصوصية هذه.',
                style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const SizedBox(height: 6),
          Text(body,
              style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.7)),
        ],
      ),
    );
  }
}
