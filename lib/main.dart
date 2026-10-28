
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const Color navy = Color(0xFF0B1020);
const Color panel = Color(0xFF182440);
const Color purple = Color(0xFF8875FF);
const Color cyan = Color(0xFF64D9F7);

const List<String> subjects = [
  'مبادئ المحاسبة المالية',
  'مبادئ الاقتصاد',
  'مبادئ الإدارة',
  'لغة إنجليزية للمتخصصين',
  'رياضيات تحليل الأعمال التجارية',
  'التفكير الابتكاري',
  'إدارة رياضية',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovaApp());
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOVA Study',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const NovaHome(),
    );
  }
}

class NovaHome extends StatefulWidget {
  const NovaHome({super.key});

  @override
  State<NovaHome> createState() => _NovaHomeState();
}

class _NovaHomeState extends State<NovaHome> {
  int tab = 0;
  int subjectIndex = 0;
  bool busy = false;
  Map<String, dynamic> allData = {};

  String get subject => subjects[subjectIndex];

  Map<String, dynamic> get current {
    final data = allData[subject];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  String value(String key) => (current[key] ?? '').toString();

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('nova_data');

      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          allData = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }

    if (mounted) setState(() {});
  }

  Future<void> saveValue(String key, String text) async {
    final entry = current;
    entry[key] = text;
    allData[subject] = entry;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nova_data', jsonEncode(allData));

    if (mounted) setState(() {});
  }

  void toast(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> editContent(
    String key,
    String title, {
    String hint = '',
  }) async {
    final controller = TextEditingController(text: value(key));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              minLines: 6,
              maxLines: 16,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.start,
              decoration: InputDecoration(
                hintText: hint,
                alignLabelWithHint: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await saveValue(key, controller.text);

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                toast('تم حفظ المحتوى');
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  Future<void> pickPdf() async {
    if (busy) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null) {
        toast('لم أستطع قراءة الملف من الجهاز');
        return;
      }

      setState(() => busy = true);

      final document = sf.PdfDocument(inputBytes: bytes);

      String extracted = '';
      int pages = 0;

      try {
        pages = document.pages.count;
        extracted = sf.PdfTextExtractor(document).extractText();
      } finally {
        document.dispose();
      }

      if (extracted.trim().isEmpty) {
        toast('لم يتم العثور على نص. قد يحتاج الملف إلى OCR.');
        return;
      }

      final oldText = value('source');
      final addition =
          '\n\n===== ${file.name} | $pages صفحة =====\n$extracted';

      await saveValue('source', '$oldText$addition');
      await saveValue('filename', file.name);

      toast('تم استخراج النص من $pages صفحة');
    } catch (e) {
      toast('حدث خطأ أثناء قراءة PDF: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<List<String>> rows(String key, int minimumColumns) {
    return value(key)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.split('|').map((s) => s.trim()).toList())
        .where((row) => row.length >= minimumColumns)
        .toList();
  }

  Future<void> exportPdf() async {
    if (busy) return;

    setState(() => busy = true);

    try {
      final doc = pw.Document();

      final font = await PdfGoogleFonts.notoNaskhArabicRegular();
      final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();

      pw.TextStyle normalStyle({double size = 12}) {
        return pw.TextStyle(
          font: font,
          fontSize: size,
          color: PdfColors.black,
          lineSpacing: 4,
        );
      }

      pw.TextStyle boldStyle({
        double size = 13,
        PdfColor color = PdfColors.black,
      }) {
        return pw.TextStyle(
          font: boldFont,
          fontSize: size,
          color: color,
        );
      }

      pw.Widget section(String heading, String content) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                border: pw.Border(
                  right: pw.BorderSide(
                    color: PdfColors.red700,
                    width: 4,
                  ),
                ),
              ),
              child: pw.Text(
                heading,
                textDirection: pw.TextDirection.rtl,
                style: boldStyle(
                  size: 16,
                  color: PdfColors.red800,
                ),
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              content.isEmpty
                  ? 'لم تتم إضافة محتويات بعد.'
                  : content,
              textDirection: pw.TextDirection.rtl,
              style: normalStyle(),
            ),
          ],
        );
      }

      final terms = rows('terms', 2);
      final questions = rows('questions', 7);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(34),
          theme: pw.ThemeData.withFont(
            base: font,
            bold: boldFont,
          ),
          header: (_) {
            return pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                'NOVA STUDY',
                style: boldStyle(
                  size: 12,
                  color: PdfColors.blue800,
                ),
              ),
            );
          },
          footer: (context) {
            return pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'NOVA Study • ${context.pageNumber}',
                style: normalStyle(size: 9),
              ),
            );
          },
          build: (_) => [
            pw.Center(
              child: pw.Text(
                subject,
                textDirection: pw.TextDirection.rtl,
                style: boldStyle(
                  size: 22,
                  color: PdfColors.blue900,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'شرح مبسط | Arabic + English',
                textDirection: pw.TextDirection.rtl,
                style: boldStyle(size: 13),
              ),
            ),
            section('الشرح المبسط', value('notes')),
            section('القوانين والقواعد المهمة', value('laws')),
            section('الكلمات والعبارات المفتاحية', value('keywords')),
            if (terms.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Important Terms | المصطلحات المهمة',
                style: boldStyle(
                  size: 17,
                  color: PdfColors.red800,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['English', 'العربي', 'Explanation'],
                data: terms.map((r) {
                  return [
                    r[0],
                    r[1],
                    r.length > 2 ? r.sublist(2).join(' | ') : '',
                  ];
                }).toList(),
                headerStyle: boldStyle(size: 10),
                cellStyle: normalStyle(size: 10),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue100,
                ),
                cellPadding: const pw.EdgeInsets.all(6),
                border: pw.TableBorder.all(
                  color: PdfColors.blueGrey200,
                  width: .5,
                ),
              ),
            ],
            if (questions.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Practice Questions | أسئلة التدريب',
                style: boldStyle(
                  size: 17,
                  color: PdfColors.red800,
                ),
              ),
              ...questions.asMap().entries.map((entry) {
                final q = entry.value;
                final parsed = int.tryParse(q[5]) ?? 1;
                final correct = parsed.clamp(1, 4).toInt();

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Q${entry.key + 1}. ${q[0]}',
                      style: boldStyle(
                        size: 12,
                        color: PdfColors.red800,
                      ),
                    ),
                    for (int i = 1; i <= 4; i++)
                      pw.Text(
                        '${String.fromCharCode(64 + i)}. ${q[i]}',
                        style: normalStyle(size: 11),
                      ),
                    pw.Text(
                      'Answer: ${String.fromCharCode(64 + correct)}. ${q[correct]}',
                      style: boldStyle(size: 11),
                    ),
                    pw.Text(
                      'Explanation / الشرح: ${q.sublist(6).join(' | ')}',
                      textDirection: pw.TextDirection.rtl,
                      style: normalStyle(size: 11),
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'NOVA_Study_${subjectIndex + 1}.pdf',
      );

      toast('تم إنشاء المذكرة وفتح خيارات المشاركة');
    } catch (e) {
      toast('خطأ في إنشاء PDF: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget card(Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }

  Widget action(
    String title,
    IconData icon,
    VoidCallback callback, {
    String? subtitle,
  }) {
    return card(
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: cyan, size: 29),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: callback,
      ),
    );
  }

  Widget picker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<int>(
        value: subjectIndex,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'اختار المادة',
          prefixIcon: Icon(Icons.school, color: cyan),
        ),
        items: List.generate(
          subjects.length,
          (i) => DropdownMenuItem<int>(
            value: i,
            child: Text(
              subjects[i],
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        onChanged: (v) {
          if (v != null) setState(() => subjectIndex = v);
        },
      ),
    );
  }

  Widget homePage() {
    return Column(
      children: [
        card(
          const Column(
            children: [
              Icon(Icons.auto_awesome, color: cyan, size: 48),
              SizedBox(height: 10),
              Text(
                'NOVA STUDY',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 8),
              Text('مساعد المذاكرة الجامعية'),
              SizedBox(height: 6),
              Text(
                'موادك • مذكراتك • امتحاناتك',
                style: TextStyle(color: cyan),
              ),
            ],
          ),
        ),
        const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'المواد الدراسية السبعة',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        ...List.generate(
          subjects.length,
          (i) => action(
            subjects[i],
            Icons.menu_book,
            () {
              setState(() {
                subjectIndex = i;
                tab = 1;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget studyPage() {
    return Column(
      children: [
        picker(),
        action(
          'رفع وقراءة ملف PDF',
          Icons.picture_as_pdf,
          pickPdf,
          subtitle: value('filename').isEmpty
              ? 'اختار ملف محاضرة من جهازك'
              : 'آخر ملف: ${value('filename')}',
        ),
        action(
          'عرض النص المستخرج من المحاضرات',
          Icons.article_outlined,
          () => editContent('source', 'نص المحاضرات'),
        ),
        action(
          'الشرح المبسط بالعربي والإنجليزي',
          Icons.menu_book,
          () => editContent(
            'notes',
            'الشرح المبسط',
            hint: 'اكتب الشرح بالعربي والمصطلحات الإنجليزية والأمثلة.',
          ),
        ),
        action(
          'القوانين والقواعد',
          Icons.calculate_outlined,
          () => editContent('laws', 'القوانين والقواعد المهمة'),
        ),
        action(
          'الكلمات المفتاحية',
          Icons.key,
          () => editContent('keywords', 'الكلمات والعبارات المهمة'),
        ),
        action(
          'إضافة المصطلحات في جدول',
          Icons.table_chart,
          () => editContent(
            'terms',
            'جدول المصطلحات',
            hint: 'كل سطر بالشكل التالي:\n'
                'English term | المصطلح العربي | Explanation\n'
                'Assets | الأصول | Economic resources',
          ),
        ),
        action(
          'إضافة الأسئلة والإجابات',
          Icons.quiz_outlined,
          () => editContent(
            'questions',
            'بنك الأسئلة',
            hint: 'كل سؤال في سطر واحد، وافصل الخانات بعلامة |\n'
                'Question | Option A | Option B | Option C | Option D | رقم الإجابة الصحيحة (1-4) | الشرح\n'
                'What is an asset? | Cash | Loan | Expense | Loss | 1 | Cash is a resource',
          ),
        ),
        action(
          'إنشاء وتصدير مذكرة PDF',
          Icons.picture_as_pdf,
          exportPdf,
          subtitle: 'حفظ أو مشاركة المذكرة',
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget termsPage() {
    final list = rows('terms', 2);

    return Column(
      children: [
        picker(),
        action(
          'إضافة أو تعديل المصطلحات',
          Icons.edit,
          () => editContent(
            'terms',
            'المصطلحات',
            hint: 'English | العربي | Explanation',
          ),
        ),
        if (list.isEmpty)
          card(
            const Text(
              'لا توجد مصطلحات محفوظة لهذه المادة بعد.',
              textAlign: TextAlign.center,
            ),
          ),
        ...list.map(
          (r) => card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  r[0],
                  style: const TextStyle(
                    color: cyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  r[1],
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (r.length > 2) ...[
                  const SizedBox(height: 6),
                  Text(r.sublist(2).join(' | ')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget examPage() {
    final list = rows('questions', 7);

    return Column(
      children: [
        picker(),
        card(
          Column(
            children: [
              const Icon(Icons.fact_check, color: cyan, size: 50),
              const SizedBox(height: 10),
              const Text(
                'Practice Exams',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text('عدد الأسئلة المضافة: ${list.length}'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: list.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExamScreen(
                                title: subject,
                                questions: list,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ابدأ الامتحان'),
                ),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          const Text(
            'أضف الأسئلة من صفحة المذاكرة أولًا.',
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(),
      studyPage(),
      examPage(),
      termsPage(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'NOVA Study',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.auto_awesome, color: cyan),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey(tab),
                  child: pages[tab],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: panel,
          selectedIndex: tab,
          indicatorColor: purple.withOpacity(.3),
          onDestinationSelected: (index) {
            setState(() => tab = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book),
              label: 'المذاكرة',
            ),
            NavigationDestination(
              icon: Icon(Icons.quiz_outlined),
              label: 'الامتحانات',
            ),
            NavigationDestination(
              icon: Icon(Icons.translate),
              label: 'المصطلحات',
            ),
          ],
        ),
      ),
    );
  }
}

class ExamScreen extends StatefulWidget {
  final String title;
  final List<List<String>> questions;

  const ExamScreen({
    super.key,
    required this.title,
    required this.questions,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late List<List<String>> questions;
  final Map<int, int> selected = {};
  bool corrected = false;

  @override
  void initState() {
    super.initState();
    questions = List<List<String>>.from(widget.questions);
    questions.shuffle();
  }

  int get score {
    int result = 0;

    for (int i = 0; i < questions.length; i++) {
      final correct = int.tryParse(questions[i][5]) ?? 0;
      if (selected[i] == correct) result++;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (corrected)
              Card(
                color: panel,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: cyan,
                        size: 48,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'نتيجتك: $score / ${questions.length}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        questions.isEmpty
                            ? '0%'
                            : '${(score * 100 / questions.length).round()}%',
                        style: const TextStyle(
                          color: cyan,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ...questions.asMap().entries.map((entry) {
              final i = entry.key;
              final q = entry.value;
              final answer =
                  (int.tryParse(q[5]) ?? 1).clamp(1, 4).toInt();

              return Card(
                color: panel,
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سؤال ${i + 1}: ${q[0]}',
                        style: const TextStyle(
                          color: cyan,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(4, (optionIndex) {
                        final option = optionIndex + 1;

                        return RadioListTile<int>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: option,
                          groupValue: selected[i],
                          title: Text(
                            '${String.fromCharCode(64 + option)}. ${q[option]}',
                          ),
                          onChanged: corrected
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() => selected[i] = v);
                                  }
                                },
                        );
                      }),
                      if (corrected) ...[
                        const Divider(),
                        Text(
                          'الإجابة الصحيحة: ${String.fromCharCode(64 + answer)}. ${q[answer]}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('التفسير: ${q.sublist(6).join(' | ')}'),
                      ],
                    ],
                  ),
                ),
              );
            }),
            FilledButton.icon(
              onPressed: corrected
                  ? () {
                      setState(() {
                        selected.clear();
                        questions.shuffle();
                        corrected = false;
                      });
                    }
                  : () {
                      if (selected.length < questions.length) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('جاوب على كل الأسئلة الأول'),
                          ),
                        );
                        return;
                      }

                      setState(() => corrected = true);
                    },
              icon: Icon(
                corrected ? Icons.refresh : Icons.check_circle,
              ),
              label: Text(
                corrected ? 'إعادة الامتحان' : 'تصحيح الامتحان',
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
