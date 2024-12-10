import 'dart:math' as math;

import 'package:leap/leap.dart';
import 'package:leap/src/physical_behaviors/physical_behaviors.dart';

/// Contains all the logic for the collision detection system,
/// updates the [velocity], [x], [y], and [collisionInfo] as needed.
class CollisionDetectionBehavior extends PhysicalBehavior {
  CollisionDetectionBehavior() : prevCollisionInfo = CollisionInfo();

  /// The previous collision information of the entity.
  final CollisionInfo prevCollisionInfo;

  /// Temporal hits list, used to store collision during detection.
  final List<PhysicalEntity> _tmpHits = [];

  /// Used to test intersections.
  final _hitboxProxy = _HitboxProxyComponent();

  @override
  void onMount() {
    super.onMount();
    _hitboxProxy.overrideGameRef = parent.gameRef;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isRemoving) {
      return;
    }

    prevCollisionInfo.copyFrom(collisionInfo);
    collisionInfo.reset();

    groundCollisionDetection(dt);
    nonMapCollisionDetection(dt);
  }

  void nonMapCollisionDetection(double dt) {
    final nonMapCollidables = world.physicals.where(
      (other) =>
          other.collisionType == CollisionType.standard &&
          !parent.isOtherSolid(other),
    );
    for (final other in nonMapCollidables) {
      if (intersects(other)) {
        collisionInfo.otherCollisions ??= [];
        collisionInfo.otherCollisions!.add(other);
      }
    }
  }

  /// Handles tilemap ground collisions
  void groundCollisionDetection(double dt) {
    _proxyHitboxForHorizontalMovement(dt);

    // Check horizontal collisions
    if (velocity.x > 0) {
      // Moving right
      _calculateTilemapHits((c) {
        return c.left <= _hitboxProxy.right &&
            c.right >= _hitboxProxy.right &&
            !c.tags.contains('platform');
      });

      if (_tmpHits.isNotEmpty) {
        _tmpHits.sort((a, b) => a.left.compareTo(b.left));
        final firstRightHit = _tmpHits.first;
        if (firstRightHit.isSlopeFromLeft) {
          if (velocity.y >= 0) {
            collisionInfo.downCollision = firstRightHit;
          } else {
            collisionInfo.rightCollision = firstRightHit;
          }
        } else if (firstRightHit.left >= right) {
          collisionInfo.rightCollision = firstRightHit;
        }
      }
    }

    if (velocity.x < 0) {
      // Moving left
      _calculateTilemapHits((c) {
        return c.left <= _hitboxProxy.left &&
            c.right >= _hitboxProxy.left &&
            !c.tags.contains('platform');
      });

      if (_tmpHits.isNotEmpty) {
        _tmpHits.sort((a, b) => b.right.compareTo(a.right));
        final firstLeftHit = _tmpHits.first;
        if (firstLeftHit.isSlopeFromRight) {
          if (velocity.y >= 0) {
            collisionInfo.downCollision = firstLeftHit;
          } else {
            collisionInfo.leftCollision = firstLeftHit;
          }
        } else if (firstLeftHit.right <= left) {
          collisionInfo.leftCollision = firstLeftHit;
        }
      }
    }

    _proxyHitboxForVerticalMovement(dt);

    // Check vertical collisions
    if (velocity.y > 0 && !collisionInfo.down && !collisionInfo.onSlope) {
      // Moving down
      _calculateTilemapHits((c) {
        return c.bottom >= bottom &&
            c.relativeTop(_hitboxProxy) <= _hitboxProxy.bottom;
      });

      if (_tmpHits.isNotEmpty) {
        _tmpHits.sort((a, b) {
          if (a.isSlope && !b.isSlope) {
            return -1;
          } else if (!a.isSlope && b.isSlope) {
            return 1;
          }
          return a.relativeTop(_hitboxProxy).compareTo(b.top);
        });
        final firstBottomHit = _tmpHits.first;
        collisionInfo.downCollision = firstBottomHit;
      }
    }

    if (velocity.y < 0) {
      // Moving up
      _calculateTilemapHits((c) {
        return c.top <= top &&
            c.bottom >= _hitboxProxy.top &&
            !c.tags.contains('platform');
      });

      if (_tmpHits.isNotEmpty) {
        _tmpHits.sort((a, b) => a.bottom.compareTo(b.bottom));
        final firstTopHit = _tmpHits.first;
        collisionInfo.upCollision = firstTopHit;
      }
    }

    // Handling walking downhill across slopes
    if (velocity.y > 0 &&
        !collisionInfo.down &&
        prevCollisionInfo.down &&
        prevCollisionInfo.downCollision!.gridX >= 0 &&
        prevCollisionInfo.downCollision!.gridY >= 0) {
      final prevDown = prevCollisionInfo.downCollision!;
      if (velocity.x > 0) {
        // Walking down slope to the right.
        final nextSlopeYDelta = prevDown.rightTop == 0 ? 1 : 0;

        int nextX = prevDown.gridX + 1;
        int nextY = prevDown.gridY + nextSlopeYDelta;

        if (nextX >= 0 &&
            nextX < map.groundTiles.length &&
            nextY >= 0 &&
            nextY < map.groundTiles[nextX].length) {
          final nextSlope = map.groundTiles[nextX][nextY];
          if (prevDown.right >= left) {
            collisionInfo.downCollision = prevDown;
          } else if (nextSlope != null && nextSlope.isSlopeFromRight) {
            collisionInfo.downCollision = nextSlope;
          }
        }
      } else if (velocity.x < 0) {
        // Walking down slope to the left.
        final nextSlopeYDelta = prevDown.leftTop == 0 ? 1 : 0;

        int nextX = prevDown.gridX - 1;
        int nextY = prevDown.gridY + nextSlopeYDelta;

        if (nextX >= 0 &&
            nextX < map.groundTiles.length &&
            nextY >= 0 &&
            nextY < map.groundTiles[nextX].length) {
          final nextSlope = map.groundTiles[nextX][nextY];
          if (prevDown.left <= right) {
            collisionInfo.downCollision = prevDown;
          } else if (nextSlope != null && nextSlope.isSlopeFromLeft) {
            collisionInfo.downCollision = nextSlope;
          }
        }
      }
    }
  }

  void _proxyHitboxForVerticalMovement(double dt) {
    _hitboxProxy.x = x;
    _hitboxProxy.width = width;
    if (velocity.y > 0) {
      _hitboxProxy.y = y;
    } else {
      _hitboxProxy.y = y + velocity.y * dt;
    }
    _hitboxProxy.height = height + velocity.y.abs() * dt;
  }

  void _proxyHitboxForHorizontalMovement(double dt) {
    _hitboxProxy.y = y;
    _hitboxProxy.height = height;
    if (velocity.x > 0) {
      _hitboxProxy.x = x;
    } else {
      _hitboxProxy.x = x + velocity.x * dt;
    }
    _hitboxProxy.width = width + velocity.x.abs() * dt;
  }

  void _calculateTilemapHits(bool Function(PhysicalEntity) filter) {
    _tmpHits.clear();

    final maxXTile = map.groundTiles.length - 1;
    final maxYTile = map.groundTiles[0].length - 1;

    final leftTile = math.max(0, _hitboxProxy.gridLeft - 1);
    final rightTile = math.min(maxXTile, _hitboxProxy.gridRight + 1);
    final topTile = math.max(0, _hitboxProxy.gridTop - 1);
    final bottomTile = math.min(maxYTile, _hitboxProxy.gridBottom + 1);

    for (var j = leftTile; j <= rightTile; j++) {
      for (var i = topTile; i <= bottomTile; i++) {
        final tile = map.groundTiles[j][i];
        if (tile != null &&
            intersectsOther(_hitboxProxy, tile) &&
            tile.collisionType == CollisionType.tilemapGround &&
            filter(tile)) {
          _tmpHits.add(tile);
        }
      }
    }

    final nonMapCollidables = world.physicals.where(
      (p) => p.collisionType == CollisionType.standard,
    );
    for (final other in nonMapCollidables) {
      if (intersectsOther(_hitboxProxy, other) &&
          parent.isOtherSolid(other) &&
          filter(other)) {
        _tmpHits.add(other);
      }
    }
  }

  static bool intersectsOther(PhysicalEntity a, PhysicalEntity b) {
    final bHeight = b.bottom - b.relativeTop(a);
    return ((a.centerX - b.centerX).abs() * 2 < (a.width + b.width)) &&
        ((a.centerY - (b.bottom - (bHeight / 2))).abs() * 2 <
            (a.height + bHeight));
  }

  bool intersects(PhysicalEntity b) {
    final bHeight = b.bottom - b.relativeTop(parent);
    return ((centerX - b.centerX).abs() * 2 < (width + b.width)) &&
        ((centerY - (b.bottom - (bHeight / 2))).abs() * 2 <
            (height + bHeight));
  }
}

class _HitboxProxyComponent extends PhysicalEntity {
  _HitboxProxyComponent() : super(static: true);

  late LeapGame overrideGameRef;

  @override
  LeapGame get gameRef => overrideGameRef;
}
