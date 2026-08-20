import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';

import '../repositories/project_repository.dart';

/// What kind of sound an entry produces.
enum SoundKind { effect, bed }

/// One entry in the built-in sound library.
class SoundDef {
  const SoundDef({
    required this.id,
    required this.name,
    required this.category,
    required this.kind,
    required this.duration,
    this.icon = '',
  });

  final String id;
  final String name;
  final String category;
  final SoundKind kind;
  final Duration duration;
  final String icon;
}

/// A note in a generated musical loop: semitones from A3, beat index, and
/// how long it rings.
class _Note {
  const _Note(this.semitone, this.beat, this.decay, {this.gain = 0.22});

  final int semitone;
  final double beat;
  final double decay;
  final double gain;

  /// Equal temperament from A3 = 220 Hz.
  double get frequency => 220.0 * math.pow(2, semitone / 12.0);
}

/// The built-in sound library.
///
/// Nothing here is a recording — every sound is synthesised on device with
/// FFmpeg's `aevalsrc`, which is why the app can ship a usable library at all
/// without licensing anyone's audio. Files are generated once and cached.
class SoundLibrary {
  SoundLibrary._();

  static final SoundLibrary instance = SoundLibrary._();

  static const int _sampleRate = 48000;

  static const List<String> categories = [
    'Beds', 'Riser', 'Whoosh', 'Impact', 'UI', 'Tone'
  ];

  static const List<SoundDef> all = [
    // Musical loops
    SoundDef(id: 'bedLofi', name: 'Lo-fi', category: 'Beds',
        kind: SoundKind.bed, duration: Duration(seconds: 8), icon: '🎧'),
    SoundDef(id: 'bedAmbient', name: 'Ambient', category: 'Beds',
        kind: SoundKind.bed, duration: Duration(seconds: 8), icon: '🌌'),
    SoundDef(id: 'bedUpbeat', name: 'Upbeat', category: 'Beds',
        kind: SoundKind.bed, duration: Duration(seconds: 8), icon: '⚡'),
    SoundDef(id: 'bedCinematic', name: 'Cinematic', category: 'Beds',
        kind: SoundKind.bed, duration: Duration(seconds: 8), icon: '🎬'),
    SoundDef(id: 'bedChill', name: 'Chill', category: 'Beds',
        kind: SoundKind.bed, duration: Duration(seconds: 8), icon: '🌊'),
    SoundDef(id: 'bedMinimal', name: 'Minimal', category: 'Beds',
        kind: SoundKind.bed, duration: Duration(seconds: 8), icon: '◽'),
    // Risers
    SoundDef(id: 'riserShort', name: 'Riser', category: 'Riser',
        kind: SoundKind.effect, duration: Duration(milliseconds: 1500), icon: '📈'),
    SoundDef(id: 'riserLong', name: 'Long Rise', category: 'Riser',
        kind: SoundKind.effect, duration: Duration(seconds: 3), icon: '🚀'),
    SoundDef(id: 'fallDown', name: 'Fall', category: 'Riser',
        kind: SoundKind.effect, duration: Duration(milliseconds: 1400), icon: '📉'),
    SoundDef(id: 'sweepUp', name: 'Sweep', category: 'Riser',
        kind: SoundKind.effect, duration: Duration(milliseconds: 1200), icon: '🌀'),
    // Whooshes
    SoundDef(id: 'whoosh', name: 'Whoosh', category: 'Whoosh',
        kind: SoundKind.effect, duration: Duration(milliseconds: 700), icon: '💨'),
    SoundDef(id: 'whooshLong', name: 'Slow Air', category: 'Whoosh',
        kind: SoundKind.effect, duration: Duration(milliseconds: 1400), icon: '🍃'),
    SoundDef(id: 'swishFast', name: 'Swish', category: 'Whoosh',
        kind: SoundKind.effect, duration: Duration(milliseconds: 380), icon: '⚔️'),
    SoundDef(id: 'transitionAir', name: 'Air Cut', category: 'Whoosh',
        kind: SoundKind.effect, duration: Duration(milliseconds: 500), icon: '✂️'),
    // Impacts
    SoundDef(id: 'impactDeep', name: 'Boom', category: 'Impact',
        kind: SoundKind.effect, duration: Duration(milliseconds: 1200), icon: '💥'),
    SoundDef(id: 'impactHit', name: 'Hit', category: 'Impact',
        kind: SoundKind.effect, duration: Duration(milliseconds: 600), icon: '🥊'),
    SoundDef(id: 'impactThud', name: 'Thud', category: 'Impact',
        kind: SoundKind.effect, duration: Duration(milliseconds: 450), icon: '🪵'),
    SoundDef(id: 'kick', name: 'Kick', category: 'Impact',
        kind: SoundKind.effect, duration: Duration(milliseconds: 300), icon: '🦶'),
    // UI
    SoundDef(id: 'click', name: 'Click', category: 'UI',
        kind: SoundKind.effect, duration: Duration(milliseconds: 90), icon: '🖱️'),
    SoundDef(id: 'pop', name: 'Pop', category: 'UI',
        kind: SoundKind.effect, duration: Duration(milliseconds: 170), icon: '🫧'),
    SoundDef(id: 'tick', name: 'Tick', category: 'UI',
        kind: SoundKind.effect, duration: Duration(milliseconds: 70), icon: '⏱️'),
    SoundDef(id: 'chime', name: 'Chime', category: 'UI',
        kind: SoundKind.effect, duration: Duration(milliseconds: 1400), icon: '🔔'),
    SoundDef(id: 'success', name: 'Success', category: 'UI',
        kind: SoundKind.effect, duration: Duration(milliseconds: 900), icon: '✅'),
    SoundDef(id: 'error', name: 'Error', category: 'UI',
        kind: SoundKind.effect, duration: Duration(milliseconds: 600), icon: '⛔'),
    // Tones
    SoundDef(id: 'beep', name: 'Beep', category: 'Tone',
        kind: SoundKind.effect, duration: Duration(milliseconds: 250), icon: '📢'),
    SoundDef(id: 'countIn', name: 'Count In', category: 'Tone',
        kind: SoundKind.effect, duration: Duration(seconds: 2), icon: '🔢'),
    SoundDef(id: 'heartbeat', name: 'Heartbeat', category: 'Tone',
        kind: SoundKind.effect, duration: Duration(seconds: 2), icon: '❤️'),
    SoundDef(id: 'suspense', name: 'Suspense', category: 'Tone',
        kind: SoundKind.effect, duration: Duration(seconds: 3), icon: '😰'),
  ];

  static List<SoundDef> byCategory(String c) =>
      all.where((s) => s.category == c).toList();

  final Map<String, String> _cache = {};

  Future<Directory> _dir() async {
    final base = await ProjectRepository.instance.mediaDir();
    final d = Directory('${base.path}/sounds');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Path to the rendered sound, generating it the first time it is used.
  Future<String?> resolve(SoundDef def) async {
    final cached = _cache[def.id];
    if (cached != null && await File(cached).exists()) return cached;

    final dir = await _dir();
    final out = '${dir.path}/${def.id}.m4a';
    if (await File(out).exists()) {
      _cache[def.id] = out;
      return out;
    }

    final command = def.kind == SoundKind.bed
        ? _bedCommand(def, out)
        : _effectCommand(def, out);
    if (command == null) return null;

    try {
      final session = await FFmpegKit.execute(command);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        debugPrint('sound gen failed for ${def.id}: '
            '${await session.getAllLogsAsString()}');
        return null;
      }
      _cache[def.id] = out;
      return out;
    } catch (e) {
      debugPrint('sound gen threw for ${def.id}: $e');
      return null;
    }
  }

  // ------------------------------------------------------------- synthesis

  /// A one-shot effect is a single `aevalsrc` expression.
  ///
  /// Expressions are kept comma-free because `aevalsrc` treats a bare comma as
  /// the end of the filter; writing them additively instead of with `if()`
  /// avoids an escaping minefield.
  String? _effectCommand(SoundDef def, String out) {
    final d = def.duration.inMilliseconds / 1000;
    final expr = switch (def.id) {
      // Frequency sweeps: phase is the integral of frequency, so a linear
      // sweep needs a t^2 term or it drifts audibly flat.
      'riserShort' => '0.34*sin(2*PI*(180*t+520*t*t/${d.toStringAsFixed(3)}))'
          '*(t/${d.toStringAsFixed(3)})',
      'riserLong' => '0.3*sin(2*PI*(120*t+900*t*t/${d.toStringAsFixed(3)}))'
          '*(t/${d.toStringAsFixed(3)})',
      'fallDown' => '0.32*sin(2*PI*(900*t-620*t*t/${d.toStringAsFixed(3)}))'
          '*exp(-1.4*t)',
      'sweepUp' => '0.26*(random(0)-0.5)*2*(t/${d.toStringAsFixed(3)})'
          '+0.16*sin(2*PI*(240*t+700*t*t/${d.toStringAsFixed(3)}))',

      // Noise shaped by an envelope reads as moving air.
      'whoosh' => '0.4*(random(0)-0.5)*2*exp(-3.2*t)*(1-exp(-26*t))',
      'whooshLong' => '0.34*(random(0)-0.5)*2*exp(-1.5*t)*(1-exp(-7*t))',
      'swishFast' => '0.42*(random(0)-0.5)*2*exp(-11*t)*(1-exp(-70*t))',
      'transitionAir' => '0.36*(random(0)-0.5)*2*exp(-6*t)*(1-exp(-40*t))'
          '+0.1*sin(2*PI*(700*t+900*t*t))*exp(-6*t)',

      // Impacts: a low sine with a fast decay, plus a noise transient.
      'impactDeep' => '0.55*sin(2*PI*52*t)*exp(-3.4*t)'
          '+0.5*sin(2*PI*38*t)*exp(-2.2*t)'
          '+0.2*(random(0)-0.5)*2*exp(-40*t)',
      'impactHit' => '0.5*sin(2*PI*90*t)*exp(-9*t)'
          '+0.3*(random(0)-0.5)*2*exp(-30*t)',
      'impactThud' => '0.5*sin(2*PI*70*t)*exp(-14*t)'
          '+0.14*(random(0)-0.5)*2*exp(-60*t)',
      'kick' => '0.6*sin(2*PI*(120*t-70*t*t/0.3))*exp(-16*t)',

      // UI: short transients and small melodies.
      'click' => '0.4*(random(0)-0.5)*2*exp(-90*t)',
      'pop' => '0.45*sin(2*PI*(520*t+300*t*t))*exp(-26*t)',
      'tick' => '0.34*sin(2*PI*2400*t)*exp(-120*t)',
      'chime' => '0.24*sin(2*PI*1046*t)*exp(-2.6*t)'
          '+0.18*sin(2*PI*1568*t)*exp(-3.1*t)'
          '+0.12*sin(2*PI*2093*t)*exp(-3.8*t)',
      'success' => '0.26*sin(2*PI*784*t)*exp(-7*t)'
          '+0.26*sin(2*PI*1046*t)*exp(-5*t)*(1-exp(-40*(t-0.12)))'
          '*(1+sgn(t-0.12))/2',
      'error' => '0.3*sin(2*PI*220*t)*exp(-5*t)'
          '+0.22*sin(2*PI*180*t)*exp(-4*t)',

      // Tones
      'beep' => '0.34*sin(2*PI*880*t)*exp(-8*t)*(1-exp(-200*t))',
      // One beep every half second: mod() restarts the decay envelope, and
      // the second thump of the heartbeat is phase-shifted rather than gated,
      // which avoids a discontinuity at the beat boundary.
      'countIn' => '0.34*sin(2*PI*1000*t)*exp(-30*mod(t,0.5))'
          '*(1-exp(-400*mod(t,0.5)))',
      'heartbeat' => '0.5*sin(2*PI*48*t)*exp(-14*mod(t,1))'
          '+0.34*sin(2*PI*44*t)*exp(-17*mod(t+0.72,1))',
      'suspense' => '0.2*sin(2*PI*110*t)+0.14*sin(2*PI*164.8*t)'
          '+0.1*sin(2*PI*220*t)*(0.6+0.4*sin(2*PI*0.7*t))',
      _ => null,
    };
    if (expr == null) return null;

    // A short fade at both ends removes the click a hard cut would leave.
    final fadeOut = math.max(d - 0.03, 0.0);
    // The expression is single-quoted: commas inside mod()/if() would
    // otherwise terminate the filter.
    return '-hide_banner -y -f lavfi '
        '-i "aevalsrc=exprs=\'$expr\':duration=${d.toStringAsFixed(3)}'
        ':sample_rate=$_sampleRate:channel_layout=mono" '
        '-af "afade=t=in:st=0:d=0.006,'
        'afade=t=out:st=${fadeOut.toStringAsFixed(3)}:d=0.03,'
        'alimiter=limit=0.95,aformat=channel_layouts=stereo" '
        '-c:a aac -b:a 192k "$out"';
  }

  /// A musical loop is built note by note: each note is its own generated
  /// input, delayed onto its beat and mixed. That keeps every expression
  /// trivial and gives real arpeggios rather than a drone.
  String? _bedCommand(SoundDef def, String out) {
    final (notes, bpm, tone) = _bedVoicing(def.id);
    if (notes.isEmpty) return null;

    final beatSeconds = 60.0 / bpm;
    final inputs = <String>[];
    final chains = <String>[];
    final labels = <String>[];

    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final f = n.frequency.toStringAsFixed(3);
      final ring = math.min(n.decay, def.duration.inMilliseconds / 1000);
      // Two partials per note so it reads as an instrument, not a test tone.
      final expr = '${n.gain.toStringAsFixed(3)}*sin(2*PI*$f*t)'
          '*exp(-${(3.0 / ring).toStringAsFixed(3)}*t)'
          '+${(n.gain * 0.35).toStringAsFixed(3)}*sin(2*PI*${(n.frequency * 2).toStringAsFixed(3)}*t)'
          '*exp(-${(5.0 / ring).toStringAsFixed(3)}*t)';
      inputs.add('-f lavfi -i "aevalsrc=exprs=\'$expr\''
          ':duration=${ring.toStringAsFixed(3)}'
          ':sample_rate=$_sampleRate:channel_layout=mono"');
      final delayMs = (n.beat * beatSeconds * 1000).round();
      chains.add('[$i:a]adelay=$delayMs,apad=whole_dur='
          '${(def.duration.inMilliseconds / 1000).toStringAsFixed(3)}[n$i]');
      labels.add('[n$i]');
    }

    final mix = '${labels.join()}amix=inputs=${labels.length}'
        ':duration=first:normalize=0';
    final voice = '$mix,$tone,'
        'atrim=0:${(def.duration.inMilliseconds / 1000).toStringAsFixed(3)},'
        'afade=t=in:st=0:d=0.05,'
        'afade=t=out:st=${(def.duration.inMilliseconds / 1000 - 0.25).toStringAsFixed(3)}:d=0.25,'
        'alimiter=limit=0.92,'
        'aformat=channel_layouts=stereo[outa]';

    return '-hide_banner -y ${inputs.join(' ')} '
        '-filter_complex "${chains.join(';')};$voice" '
        '-map "[outa]" -c:a aac -b:a 192k "$out"';
  }

  /// Chord voicings per bed, as (notes, bpm, post-processing chain).
  (List<_Note>, double, String) _bedVoicing(String id) {
    switch (id) {
      case 'bedLofi':
        // Am7 - Fmaj7 - Cmaj7 - G, two bars each, lazy off-beat pattern.
        const chords = [
          [0, 12, 15, 19], // A minor 7
          [8, 20, 24, 27], // F major 7
          [3, 15, 19, 22], // C major 7
          [10, 22, 26, 29], // G
        ];
        final notes = <_Note>[];
        for (var bar = 0; bar < 4; bar++) {
          final chord = chords[bar];
          for (var step = 0; step < 4; step++) {
            notes.add(_Note(
              chord[step % chord.length] - 12,
              bar * 4 + step * 1.0 + (step.isOdd ? 0.12 : 0),
              2.0,
              gain: step == 0 ? 0.26 : 0.17,
            ));
          }
          notes.add(_Note(chord.first - 24, bar * 4.0, 3.2, gain: 0.3));
        }
        return (notes, 120, 'lowpass=f=1600,tremolo=f=0.6:d=0.15');

      case 'bedAmbient':
        // Sustained open fifths, no rhythm.
        const roots = [0, 7, 12, 19];
        final notes = <_Note>[
          for (var i = 0; i < roots.length; i++)
            _Note(roots[i] - 12, i * 2.0, 8.0, gain: 0.2),
          _Note(-24, 0, 8.0, gain: 0.24),
        ];
        return (notes, 60, 'lowpass=f=900,aecho=0.7:0.8:420:0.35');

      case 'bedUpbeat':
        // Driving eighth-note major arpeggio.
        const chord = [3, 7, 10, 15, 19, 22];
        final notes = <_Note>[];
        for (var step = 0; step < 32; step++) {
          notes.add(_Note(
            chord[step % chord.length] - 12,
            step * 0.5,
            0.55,
            gain: step % 4 == 0 ? 0.24 : 0.15,
          ));
        }
        return (notes, 128, 'highpass=f=120,lowpass=f=4200');

      case 'bedCinematic':
        // Slow rising minor triad with an octave pedal underneath.
        const rising = [0, 3, 7, 10, 12, 15, 19, 22];
        final notes = <_Note>[
          for (var i = 0; i < rising.length; i++)
            _Note(rising[i] - 12, i * 1.0, 3.0,
                gain: 0.14 + i * 0.012),
          _Note(-24, 0, 8.0, gain: 0.3),
          _Note(-12, 4, 5.0, gain: 0.22),
        ];
        return (notes, 90, 'lowpass=f=2200,aecho=0.8:0.85:600:0.28');

      case 'bedChill':
        // Wide, sparse maj9 with long tails.
        const chord = [0, 7, 14, 16, 23];
        final notes = <_Note>[
          for (var i = 0; i < chord.length; i++)
            _Note(chord[i] - 12, i * 1.5, 5.0, gain: 0.17),
        ];
        return (notes, 80, 'lowpass=f=1200,aecho=0.6:0.7:520:0.3');

      case 'bedMinimal':
        // Single repeated fifth, metronomic.
        final notes = <_Note>[
          for (var step = 0; step < 16; step++)
            _Note(step.isEven ? 0 : 7, step * 1.0, 0.9,
                gain: step.isEven ? 0.24 : 0.16),
        ];
        return (notes, 110, 'lowpass=f=2600');

      default:
        return (const [], 120, 'anull');
    }
  }

  /// Pre-generate the whole library so the picker never waits mid-scroll.
  Future<void> warmUp({void Function(int done, int total)? onProgress}) async {
    for (var i = 0; i < all.length; i++) {
      await resolve(all[i]);
      onProgress?.call(i + 1, all.length);
    }
  }

  Future<void> clearCache() async {
    final d = await _dir();
    if (await d.exists()) await d.delete(recursive: true);
    _cache.clear();
  }
}
