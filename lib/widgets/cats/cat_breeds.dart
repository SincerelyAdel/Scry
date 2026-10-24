import 'dart:ui';

/// A cat's coat and markings, seen from above.
class CatBreed {
  const CatBreed({
    required this.id,
    required this.base,
    required this.dark,
    required this.light,
    required this.rim,
    required this.fringe,
    required this.earIn,
    required this.nose,
    required this.eye,
    required this.muzzle,
    required this.whisker,
    this.stripe,
    this.sheen,
    this.patchA,
    this.patchB,
    this.tailColor,
    this.headPatch = false,
    this.patches = const [],
    this.points,
    this.pawColor,
    this.blaze,
    this.size = 1,
  });

  final String id;
  final Color base, dark, light, rim, fringe, earIn, nose, eye, muzzle;
  final Color whisker;

  /// Tabby stripes.
  final Color? stripe;

  /// How glossy the coat is (black cats shine more).
  final double? sheen;

  /// Calico patches: two colours, and where they sit along the back
  /// (distance from the nose, side offset, radius, which colour).
  final Color? patchA, patchB;
  final List<(double, double, double, bool)> patches;
  final bool headPatch;

  final Color? tailColor;

  /// Siamese points: darker face, ears, legs, tail.
  final Color? points;

  /// White socks (tuxedo).
  final Color? pawColor;

  /// White blaze down the face (tuxedo).
  final Color? blaze;

  /// Body size, 1 for an average cat.
  final double size;

  Color get stripeColor => stripe ?? dark;
  double get stripeOpacity => stripe != null ? 0.82 : 0;
  Color get ear => points ?? base;
  Color get legs => points ?? base;
  Color get paws => pawColor ?? points ?? base;
  Color get tail => tailColor ?? points ?? base;
  double get sheenOpacity => sheen ?? 0.16;
}

const catBreeds = [
  CatBreed(
    id: 'tabby',
    base: Color(0xFF8A6A46),
    dark: Color(0xFF3B2A1A),
    light: Color(0xFFC6A880),
    rim: Color(0xFF24180D),
    fringe: Color(0xFFB8996C),
    stripe: Color(0xFF33241A),
    earIn: Color(0xFFC9958C),
    nose: Color(0xFFA86E66),
    eye: Color(0xFFB9A43C),
    muzzle: Color(0xFFDCC7A4),
    whisker: Color(0xFFF2EDE4),
  ),
  CatBreed(
    id: 'black',
    base: Color(0xFF151518),
    dark: Color(0xFF050506),
    light: Color(0xFF626879),
    rim: Color(0xFF000000),
    fringe: Color(0xFF3C3F4A),
    earIn: Color(0xFF3B2D2E),
    nose: Color(0xFF2B2224),
    eye: Color(0xFFD9B12E),
    muzzle: Color(0xFF2C2D33),
    whisker: Color(0xFFD9D9D9),
    sheen: 0.32,
    size: 0.96,
  ),
  CatBreed(
    id: 'calico',
    base: Color(0xFFF2EDE4),
    dark: Color(0xFFB5AB9E),
    light: Color(0xFFFFFFFF),
    rim: Color(0xFF8E8478),
    fringe: Color(0xFFFFFFFF),
    patchA: Color(0xFFC9732C),
    patchB: Color(0xFF1F1A17),
    tailColor: Color(0xFFC9732C),
    earIn: Color(0xFFE7AAA4),
    nose: Color(0xFFE39C98),
    eye: Color(0xFF86A84A),
    muzzle: Color(0xFFFFFFFF),
    whisker: Color(0xFFFFFFFF),
    headPatch: true,
    size: 0.93,
    patches: [
      (37, 0.55, 7.2, true),
      (45, -0.3, 6.6, false),
      (55, 0.45, 8, false),
      (63, -0.5, 7, true),
      (69, 0.25, 5.2, true),
    ],
  ),
  CatBreed(
    id: 'siamese',
    base: Color(0xFFE9DBC5),
    dark: Color(0xFFB3A086),
    light: Color(0xFFFBF4E8),
    rim: Color(0xFF7F6C57),
    fringe: Color(0xFFF6EEDF),
    points: Color(0xFF3A2A20),
    earIn: Color(0xFF5A4036),
    nose: Color(0xFF2E211B),
    eye: Color(0xFF4E9BE0),
    muzzle: Color(0xFF3A2A20),
    whisker: Color(0xFFF4EDE2),
    size: 0.98,
  ),
  CatBreed(
    id: 'orange',
    base: Color(0xFFD6883A),
    dark: Color(0xFF8F4714),
    light: Color(0xFFF6C07E),
    rim: Color(0xFF4E270B),
    fringe: Color(0xFFF0B26C),
    stripe: Color(0xFF9A4D17),
    earIn: Color(0xFFE3A596),
    nose: Color(0xFFD88D84),
    eye: Color(0xFFC8A030),
    muzzle: Color(0xFFF4D3A6),
    whisker: Color(0xFFFFF5E8),
    size: 1.05,
  ),
  CatBreed(
    id: 'white',
    base: Color(0xFFF3F2EE),
    dark: Color(0xFFC4BEB3),
    light: Color(0xFFFFFFFF),
    rim: Color(0xFF968F84),
    fringe: Color(0xFFFFFFFF),
    earIn: Color(0xFFEDB3AF),
    nose: Color(0xFFEFA5A5),
    eye: Color(0xFF7FB2E0),
    muzzle: Color(0xFFFFFFFF),
    whisker: Color(0xFFFFFFFF),
    size: 0.9,
  ),
];
