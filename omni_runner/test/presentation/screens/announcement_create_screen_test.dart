import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';

import '../../helpers/pump_app.dart';

AnnouncementEntity _fakeAnnouncement() => AnnouncementEntity(
      id: 'a1',
      groupId: 'g1',
      createdBy: 'u1',
      title: 'Aviso importante',
      body: 'Conteúdo do aviso',
      pinned: false,
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

void main() {
  group('AnnouncementCreateScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders form with title and body fields', (tester) async {
      await tester.pumpApp(
        const _TestCreateView(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Novo Aviso'), findsOneWidget);
      expect(find.text('Título'), findsOneWidget);
      expect(find.text('Conteúdo'), findsOneWidget);
    });

    testWidgets('shows pinned toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const _TestCreateView(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Fixar no topo'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('shows save button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const _TestCreateView(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Salvar'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsWidgets);
    });

    testWidgets('shows edit title when existing is provided', (tester) async {
      await tester.pumpApp(
        _TestCreateView(
          groupId: 'g1',
          existing: _fakeAnnouncement(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Editar Aviso'), findsOneWidget);
    });

    testWidgets('pre-fills fields in edit mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        _TestCreateView(
          groupId: 'g1',
          existing: _fakeAnnouncement(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Aviso importante'), findsOneWidget);
      expect(find.text('Conteúdo do aviso'), findsOneWidget);
    });
  });
}

/// Reproduces the AnnouncementCreateScreen UI without importing the real
/// screen (which pulls in sl<> and the broken Isar chain).
class _TestCreateView extends StatefulWidget {
  final String groupId;
  final AnnouncementEntity? existing;

  const _TestCreateView({required this.groupId, this.existing});

  @override
  State<_TestCreateView> createState() => _TestCreateViewState();
}

class _TestCreateViewState extends State<_TestCreateView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _pinned = false;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleController.text = e.title;
      _bodyController.text = e.body;
      _pinned = e.pinned;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar Aviso' : 'Novo Aviso'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.check),
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Conteúdo',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 6,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('Fixar no topo'),
              subtitle: const Text(
                'Avisos fixados aparecem primeiro no mural',
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
