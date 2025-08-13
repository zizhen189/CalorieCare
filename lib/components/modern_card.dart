import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';

class ModernCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final bool hasGlassMorphism;
  final VoidCallback? onTap;
  final bool isAnimated;

  const ModernCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.hasGlassMorphism = false,
    this.onTap,
    this.isAnimated = true,
  });

  @override
  State<ModernCard> createState() => _ModernCardState();
}

class _ModernCardState extends State<ModernCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _elevationAnimation = Tween<double>(
      begin: widget.elevation ?? 4.0,
      end: (widget.elevation ?? 4.0) + 4.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasGlassMorphism) {
      return _buildGlassMorphismCard();
    }
    return _buildRegularCard();
  }

  Widget _buildGlassMorphismCard() {
    return Container(
      margin: widget.margin ?? const EdgeInsets.all(8),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: 200.0,
        borderRadius: 16,
        blur: 20,
        alignment: Alignment.bottomCenter,
        border: 2,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.5),
            Colors.white.withValues(alpha: 0.2),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: widget.padding ?? const EdgeInsets.all(16),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegularCard() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isAnimated ? _scaleAnimation.value : 1.0,
          child: Container(
            margin: widget.margin ?? const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.backgroundColor ?? Theme.of(context).cardColor,
                  (widget.backgroundColor ?? Theme.of(context).cardColor)
                      .withValues(alpha: 0.9),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                  blurRadius: widget.isAnimated ? _elevationAnimation.value : (widget.elevation ?? 4.0),
                  offset: const Offset(0, 2),
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
              child: InkWell(
                borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
                onTap: widget.onTap,
                onTapDown: widget.isAnimated ? (_) => _animationController.forward() : null,
                onTapUp: widget.isAnimated ? (_) => _animationController.reverse() : null,
                onTapCancel: widget.isAnimated ? () => _animationController.reverse() : null,
                child: Padding(
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}




