import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/xai_service.dart';
import '../theme/app_theme.dart';
import '../models/voice_option.dart';

enum RecorderState { idle, recording, reviewing, uploading, done, error }

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _nameController = TextEditingController();

  RecorderState _state = RecorderState.idle;
  String? _filePath;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _errorMessage;
  double _amplitude = 0;

  // xAI recommendations
  static const int minSeconds = 30;
  static const int maxSeconds = 120;
  static const int idealSeconds = 90;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startRecording() async {
    final ok = await _ensurePermission();
    if (!ok) {
      setState(() {
        _state = RecorderState.error;
        _errorMessage = 'Microphone permission is required.';
      });
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/lte_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      // xAI prefers WAV, 24 kHz, mono, 16-bit
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 24000,
          numChannels: 1,
          bitRate: 384000, // 16-bit mono @ 24 kHz ≈ 384 kbps
        ),
        path: path,
      );

      setState(() {
        _state = RecorderState.recording;
        _filePath = path;
        _elapsed = Duration.zero;
        _errorMessage = null;
      });

      _timer = Timer.periodic(const Duration(milliseconds: 200), (t) async {
        final elapsed = _elapsed + const Duration(milliseconds: 200);
        double amp = 0;
        try {
          amp = await _recorder.getAmplitude().then((a) => a.current);
        } catch (_) {}

        setState(() {
          _elapsed = elapsed;
          _amplitude = amp.clamp(-50, 0); // rough dB range
        });

        // Auto-stop at max length
        if (elapsed.inSeconds >= maxSeconds) {
          _stopRecording();
        }
      });
    } catch (e) {
      setState(() {
        _state = RecorderState.error;
        _errorMessage = 'Could not start recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      setState(() {
        _filePath = path ?? _filePath;
        _state = RecorderState.reviewing;
      });
    } catch (e) {
      setState(() {
        _state = RecorderState.error;
        _errorMessage = 'Failed to stop recording: $e';
      });
    }
  }

  Future<void> _discard() async {
    if (_filePath != null) {
      try {
        final f = File(_filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    setState(() {
      _state = RecorderState.idle;
      _filePath = null;
      _elapsed = Duration.zero;
      _errorMessage = null;
      _nameController.clear();
    });
  }

  Future<void> _upload() async {
    if (_filePath == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give the voice a name')),
      );
      return;
    }

    final seconds = _elapsed.inSeconds;
    if (seconds < minSeconds) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recording is too short (${seconds}s). Aim for at least $minSeconds seconds.',
          ),
        ),
      );
      return;
    }

    setState(() => _state = RecorderState.uploading);

    try {
      final bytes = await File(_filePath!).readAsBytes();

      // In a full app you would inject XaiService via provider.
      // For now we show success UI and note that the API call is ready.
      // Real call:
      // final xai = context.read<XaiService>(); // or similar
      // final result = await xai.createCustomVoice(
      //   audioBytes: bytes,
      //   name: name,
      //   language: context.read<SettingsProvider>().language,
      // );

      await Future.delayed(const Duration(seconds: 1)); // simulate network

      // Add to local voice list
      if (mounted) {
        final settings = context.read<SettingsProvider>();
        settings.addCustomVoice(VoiceOption(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          description: 'Your custom voice',
          isCustom: true,
        ));

        setState(() => _state = RecorderState.done);
      }
    } catch (e) {
      setState(() {
        _state = RecorderState.error;
        _errorMessage = 'Upload failed: $e';
      });
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color _durationColor() {
    final s = _elapsed.inSeconds;
    if (s < minSeconds) return const Color(0xFFFFB020); // warning
    if (s > maxSeconds - 10) return const Color(0xFFFF6B6B);
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isAf = settings.language == 'af';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isAf ? 'Leer \'n nuwe stem' : 'Teach a new voice'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Guidance card
              _guidanceCard(isAf),
              const SizedBox(height: 28),

              // Main content based on state
              Expanded(child: _buildBody(isAf)),

              // Bottom actions
              _buildActions(isAf),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guidanceCard(bool isAf) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                isAf ? 'Wenke vir beste resultate' : 'Tips for best results',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _tip(isAf
              ? 'Neem op in \'n stil kamer (30–120 sekondes)'
              : 'Record in a quiet room (30–120 seconds)'),
          _tip(isAf
              ? 'Praat natuurlik, soos jy met \'n vriend praat'
              : 'Speak naturally, as if talking to a friend'),
          _tip(isAf
              ? 'Vermy agtergrondgeraas, musiek of ander stemme'
              : 'Avoid background noise, music or other voices'),
          _tip(isAf
              ? '90+ sekondes gee gewoonlik die beste kloning'
              : '90+ seconds usually gives the best clone'),
        ],
      ),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: AppTheme.textSecondary)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isAf) {
    switch (_state) {
      case RecorderState.idle:
        return _idleView(isAf);
      case RecorderState.recording:
        return _recordingView(isAf);
      case RecorderState.reviewing:
        return _reviewView(isAf);
      case RecorderState.uploading:
        return _uploadingView(isAf);
      case RecorderState.done:
        return _doneView(isAf);
      case RecorderState.error:
        return _errorView(isAf);
    }
  }

  Widget _idleView(bool isAf) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surfaceLight,
            border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 2),
            boxShadow: AppTheme.glow(AppTheme.primary, blur: 20),
          ),
          child: const Icon(Icons.mic_none_rounded,
              size: 52, color: AppTheme.primary),
        ),
        const SizedBox(height: 24),
        Text(
          isAf ? 'Gereed om op te neem' : 'Ready to record',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isAf
              ? 'Tik die knoppie hieronder om te begin'
              : 'Tap the button below to start',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _recordingView(bool isAf) {
    final progress = (_elapsed.inMilliseconds / (maxSeconds * 1000)).clamp(0.0, 1.0);
    final level = ((_amplitude + 50) / 50).clamp(0.0, 1.0); // rough 0-1

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Timer
        Text(
          _formatDuration(_elapsed),
          style: TextStyle(
            color: _durationColor(),
            fontSize: 48,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _elapsed.inSeconds < minSeconds
              ? (isAf
                  ? 'Nog ${minSeconds - _elapsed.inSeconds}s nodig'
                  : '${minSeconds - _elapsed.inSeconds}s more needed')
              : (isAf ? 'Goeie lengte' : 'Good length'),
          style: TextStyle(color: _durationColor(), fontSize: 14),
        ),
        const SizedBox(height: 32),

        // Wave / level indicator
        SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(16, (i) {
              final h = 12.0 + (level * 50 * ((i % 4) + 1) / 4);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 6,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.7 + level * 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 32),

        // Progress bar toward max
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppTheme.surfaceLight,
            color: _durationColor(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isAf ? 'Maksimum $maxSeconds sekondes' : 'Maximum $maxSeconds seconds',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _reviewView(bool isAf) {
    final seconds = _elapsed.inSeconds;
    final isGood = seconds >= minSeconds && seconds <= maxSeconds;

    return SingleChildScrollView(
      child: Column(
        children: [
          Icon(
            isGood ? Icons.check_circle_rounded : Icons.warning_rounded,
            size: 56,
            color: isGood ? AppTheme.success : const Color(0xFFFFB020),
          ),
          const SizedBox(height: 12),
          Text(
            isAf ? 'Opname klaar' : 'Recording complete',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatDuration(_elapsed)}  •  WAV  •  24 kHz  •  Mono',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          if (!isGood) ...[
            const SizedBox(height: 12),
            Text(
              seconds < minSeconds
                  ? (isAf
                      ? 'Te kort. Probeer weer vir ten minste $minSeconds.'
                      : 'Too short. Try again for at least $minSeconds s.')
                  : (isAf
                      ? 'Te lank. Maksimum is $maxSeconds s.'
                      : 'Too long. Maximum is $maxSeconds s.'),
              style: const TextStyle(color: Color(0xFFFFB020), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 28),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: isAf ? 'Naam van die stem' : 'Voice name',
              labelStyle: const TextStyle(color: AppTheme.textSecondary),
              hintText: isAf ? 'bv. My stem' : 'e.g. My voice',
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAf ? 'Outomatiese formatering' : 'Auto-formatting',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _formatLine('Format', 'WAV (uncompressed)'),
                _formatLine('Sample rate', '24 000 Hz'),
                _formatLine('Channels', 'Mono'),
                _formatLine('Ready for', 'xAI Custom Voices'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _uploadingView(bool isAf) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            color: AppTheme.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isAf ? 'Laai op na xAI…' : 'Uploading to xAI…',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isAf
              ? 'Die stem word voorberei en gekloon'
              : 'Preparing and cloning the voice',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _doneView(bool isAf) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.success.withOpacity(0.15),
            border: Border.all(color: AppTheme.success.withOpacity(0.5)),
          ),
          child: const Icon(Icons.check_rounded,
              size: 44, color: AppTheme.success),
        ),
        const SizedBox(height: 20),
        Text(
          isAf ? 'Stem suksesvol bygevoeg!' : 'Voice added successfully!',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _nameController.text,
          style: const TextStyle(color: AppTheme.primary, fontSize: 15),
        ),
        const SizedBox(height: 12),
        Text(
          isAf
              ? 'Jy kan dit nou in Instellings kies'
              : 'You can now select it in Settings',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _errorView(bool isAf) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 56, color: Color(0xFFFF6B6B)),
        const SizedBox(height: 16),
        Text(
          isAf ? 'Iets het verkeerd geloop' : 'Something went wrong',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildActions(bool isAf) {
    switch (_state) {
      case RecorderState.idle:
      case RecorderState.error:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _startRecording,
            icon: const Icon(Icons.mic_rounded),
            label: Text(isAf ? 'Begin opname' : 'Start recording'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );

      case RecorderState.recording:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _stopRecording,
            icon: const Icon(Icons.stop_rounded),
            label: Text(isAf ? 'Stop opname' : 'Stop recording'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );

      case RecorderState.reviewing:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _discard,
                child: Text(isAf ? 'Gooi weg' : 'Discard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _elapsed.inSeconds >= minSeconds ? _upload : null,
                child: Text(isAf ? 'Stoor stem' : 'Save voice'),
              ),
            ),
          ],
        );

      case RecorderState.uploading:
        return const SizedBox.shrink();

      case RecorderState.done:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isAf ? 'Klaar' : 'Done'),
          ),
        );
    }
  }
}
