import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../game/sfx.dart';
import 'shell.dart';
import 'theme.dart';

/// SHOP / ARMORY.
///
/// Category tabs, a FEATURED RELEASES row of big cards, then the full
/// inventory as a dense grid. Every item shows the real in-game art, so what
/// you buy is what you get on the battlefield.
class ShopScreen extends StatefulWidget {
  final RoyaleGame game;
  const ShopScreen({super.key, required this.game});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

enum _Cat { skins, weapons, accessories, heroes, evolutions }

class _ShopItem {
  final String id;
  final String name;
  final String rarity;
  final int price;
  final bool owned;
  final Widget art;
  const _ShopItem(this.id, this.name, this.rarity, this.price, this.owned,
      this.art);
}

class _ShopScreenState extends State<ShopScreen> {
  _Cat _cat = _Cat.skins;

  static const _catLabel = {
    _Cat.skins: 'SKINS',
    _Cat.weapons: 'WEAPONS',
    _Cat.accessories: 'ACCESSORIES',
    _Cat.heroes: 'HEROES',
    _Cat.evolutions: 'EVOLUTIONS',
  };

  void _buy(_ShopItem it) {
    final p = Profile.instance;
    if (p.owns(it.id)) {
      _equip(it.id);
      return;
    }
    if (p.coins < it.price) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        backgroundColor: ZR.surface,
        duration: const Duration(seconds: 2),
        content: Text('NOT ENOUGH COINS  ·  NEED ${it.price - p.coins} MORE',
            style: ZR.display(16, color: ZR.danger)),
      ));
      return;
    }
    setState(() {
      p.buy(it.id);
      _equip(it.id);
    });
    Sfx.pickup();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: ZR.surface,
      duration: const Duration(seconds: 2),
      content: Text('${it.name.toUpperCase()} UNLOCKED  ·  EQUIPPED',
          style: ZR.display(16, color: ZR.primary)),
    ));
  }

  /// Buying something should put it on you immediately — hunting for where to
  /// equip it afterwards is the fastest way to make a shop feel broken.
  void _equip(String id) {
    final p = Profile.instance;
    final n = int.tryParse(id.substring(1)) ?? 0;
    switch (id[0]) {
      case 'o':
        p.outfit = n;
        break;
      case 'a':
        p.accessory = n;
        break;
      case 'w':
        p.startWeapon = WeaponId.values[n.clamp(0, WeaponId.values.length - 1)];
        break;
      case 'h':
        p.hero = n;
        break;
    }
    p.save();
    setState(() {});
  }

  // ---------------------------------------------------------------- data
  List<_ShopItem> _items() {
    final p = Profile.instance;
    switch (_cat) {
      case _Cat.skins:
        return [
          for (var i = 0; i < kOutfitColors.length; i++)
            _ShopItem(
              'o$i',
              i < kOutfitNames.length ? '${kOutfitNames[i]} Kit' : 'Kit ${i + 1}',
              i < 6 ? 'STANDARD ISSUE' : 'ELITE SKIN',
              p.costOf('o$i'),
              p.owns('o$i'),
              _tile(outfit: Color(kOutfitColors[i]), accent: Color(kOutfitColors[i])),
            ),
        ];
      case _Cat.weapons:
        return [
          for (final w in kWeaponOrder)
            _ShopItem(
              'w${w.index}',
              kWeapons[w]!.name,
              _weaponClass(w),
              p.costOf('w${w.index}'),
              p.owns('w${w.index}'),
              _gunTile(w),
            ),
        ];
      case _Cat.accessories:
        return [
          for (var i = 0; i < kAccessoryNames.length; i++)
            _ShopItem(
              'a$i',
              kAccessoryNames[i],
              i < 4 ? 'STANDARD ISSUE' : 'RARE GEAR',
              p.costOf('a$i'),
              p.owns('a$i'),
              _tile(accessory: i, accent: ZR.secondary, headOnly: true),
            ),
        ];
      case _Cat.heroes:
        return [
          for (var i = 0; i < kHeroes.length; i++)
            _ShopItem(
              'h$i',
              kHeroes[i].name,
              kHeroes[i].desc.split(' — ').first.toUpperCase(),
              p.costOf('h$i'),
              p.owns('h$i'),
              _tile(
                  hero: i,
                  outfit: Color(kHeroes[i].color),
                  accent: Color(kHeroes[i].color)),
            ),
        ];
      case _Cat.evolutions:
        return [
          for (var i = 0; i < kHeroes.length; i++)
            if (p.heroOwned(i))
              _ShopItem(
                'e$i',
                '${kHeroes[i].name} — Top Form',
                'HERO EVOLUTION',
                p.costOf('e$i'),
                p.owns('e$i'),
                _tile(
                    hero: i,
                    outfit: Color(kHeroes[i].color),
                    accent: ZR.primary,
                    star: true),
              ),
        ];
    }
  }

  static String _weaponClass(WeaponId w) {
    switch (w) {
      case WeaponId.sniper:
        return 'MARKSMAN · LONG RANGE';
      case WeaponId.minigun:
      case WeaponId.lmg:
        return 'HEAVY · SUPPRESSION';
      case WeaponId.shotgun:
        return 'CLOSE QUARTERS';
      case WeaponId.dmr:
        return 'PRECISION';
      default:
        return 'STANDARD ARMS';
    }
  }

  Widget _tile({
    Color? outfit,
    int accessory = -1,
    int hero = -1,
    Color accent = ZR.primary,
    bool headOnly = false,
    bool star = false,
  }) {
    final p = Profile.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _OperatorTilePainter(
            outfit: outfit ?? p.outfitColor,
            skin: p.skinColor,
            accessory: accessory < 0 ? p.accessory : accessory,
            hero: hero < 0 ? p.hero : hero,
            weapon: p.startWeapon,
            accent: accent,
            headOnly: headOnly,
          ),
        ),
        if (star)
          const Positioned(
            top: 6,
            right: 6,
            child: Icon(Icons.star, size: 15, color: ZR.primary),
          ),
      ],
    );
  }

  Widget _gunTile(WeaponId w) => CustomPaint(
        painter: _GunTilePainter(w),
      );

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return TacticalBackdrop(
      child: SafeArea(
        top: false,
        bottom: false,
        child: ZrCanvas(
          designHeight: 400,
          child: Column(
            children: [
              ZrTopBar(
                  game: widget.game, active: Screen.shop, subtitle: 'ARMORY'),
              _tabs(),
              Expanded(child: _grid()),
              ZrBottomNav(game: widget.game, active: Screen.shop),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in _Cat.values) ...[
            GestureDetector(
              onTap: () => setState(() => _cat = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _cat == c
                      ? ZR.primary
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: _cat == c ? ZR.primary : ZR.line),
                ),
                child: Text(_catLabel[c]!,
                    style: ZR.display(17,
                        color: _cat == c
                            ? const Color(0xFF10131A)
                            : Colors.white70,
                        spacing: 1)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _grid() {
    final items = _items();
    if (items.isEmpty) {
      return Center(
        child: Text('NOTHING HERE YET — UNLOCK A HERO FIRST',
            style: ZR.mono(11, color: Colors.white38, spacing: 1)),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / 155).floor().clamp(3, 8);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (_, i) => _card(items[i]),
      );
    });
  }

  Widget _card(_ShopItem it) {
    final equipped = _isEquipped(it.id);
    return GestureDetector(
      onTap: () => _buy(it),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: equipped
            ? ZR.panelActive(radius: 13)
            : ZR.panel(radius: 13, border: Colors.white12),
        child: Column(
          children: [
            Expanded(child: it.art),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(9, 5, 9, 8),
              color: Colors.black.withValues(alpha: 0.42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.rarity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZR.mono(8, color: Colors.white38, spacing: 0.8)),
                  Text(it.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZR.display(17, spacing: 0.8)),
                  const SizedBox(height: 5),
                  _priceButton(it, equipped),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isEquipped(String id) {
    final p = Profile.instance;
    final n = int.tryParse(id.substring(1)) ?? 0;
    switch (id[0]) {
      case 'o':
        return p.outfit == n;
      case 'a':
        return p.accessory == n;
      case 'w':
        return p.startWeapon.index == n;
      case 'h':
        return p.hero == n;
      default:
        return false;
    }
  }

  Widget _priceButton(_ShopItem it, bool equipped) {
    if (equipped) {
      return Container(
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ZR.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: ZR.primary),
        ),
        child: Text('EQUIPPED',
            style: ZR.display(14, color: ZR.primary, spacing: 1)),
      );
    }
    if (it.owned) {
      return Container(
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: ZR.success.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 12, color: ZR.success),
            const SizedBox(width: 5),
            Text('OWNED · TAP TO EQUIP',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: ZR.display(12, color: ZR.success, spacing: 0.5)),
          ],
        ),
      );
    }
    final afford = Profile.instance.coins >= it.price;
    return Container(
      height: 26,
      alignment: Alignment.center,
      decoration: afford
          ? ZR.cta(radius: 7)
          : BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white24),
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monetization_on,
              size: 13,
              color: afford ? const Color(0xFF10131A) : Colors.white38),
          const SizedBox(width: 5),
          Text('${it.price}',
              style: ZR.display(16,
                  color: afford ? const Color(0xFF10131A) : Colors.white38)),
        ],
      ),
    );
  }
}

/// Operator (or head close-up) on a lit stage, for character/skin tiles.
class _OperatorTilePainter extends CustomPainter {
  final Color outfit, skin, accent;
  final int accessory, hero;
  final WeaponId weapon;
  final bool headOnly;
  const _OperatorTilePainter({
    required this.outfit,
    required this.skin,
    required this.accessory,
    required this.hero,
    required this.weapon,
    required this.accent,
    required this.headOnly,
  });

  @override
  void paint(Canvas canvas, Size size) {
    drawOperatorTile(canvas, Offset.zero & size,
        outfit: outfit,
        skin: skin,
        accessory: accessory,
        hero: hero,
        weapon: weapon,
        glow: accent,
        zoom: headOnly ? 1.5 : 0.95,
        headBias: headOnly ? 0.22 : 0.0);
  }

  @override
  bool shouldRepaint(covariant _OperatorTilePainter old) =>
      old.outfit != outfit ||
      old.accessory != accessory ||
      old.hero != hero ||
      old.weapon != weapon;
}

/// The gun itself, angled, on a lit stage.
class _GunTilePainter extends CustomPainter {
  final WeaponId weapon;
  const _GunTilePainter(this.weapon);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final col = kWeapons[weapon]!.color;
    // A gun is gunmetal grey. On a near-black tile it simply disappears, so
    // the stage is lit: a lighter plate, a strong colour wash, and a bright
    // floor pool the silhouette can sit against.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF232B38), Color(0xFF0E1219)],
          ).createShader(Offset.zero & size));
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(colors: [
            col.withValues(alpha: 0.42),
            col.withValues(alpha: 0.10),
            const Color(0x00000000),
          ], stops: const [
            0.0,
            0.5,
            1.0
          ]).createShader(Offset.zero & size));
    // light pool under the weapon
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(c.dx, size.height * 0.72),
            width: size.width * 0.8,
            height: size.height * 0.22),
        Paint()..color = col.withValues(alpha: 0.16));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.40);
    // drop shadow so the silhouette reads even on the lit plate
    canvas.save();
    canvas.translate(2.5, 3.5);
    drawGunIcon(canvas, Offset.zero, size.width * 1.02, weapon,
        fill: Paint()..color = const Color(0x88000000),
        stroke: Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x88000000));
    canvas.restore();
    drawGunIcon(canvas, Offset.zero, size.width * 1.02, weapon);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GunTilePainter old) => old.weapon != weapon;
}
