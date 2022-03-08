/*
 * Copyright (C) 2019-present Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:kraken/dom.dart';
import 'package:kraken/gesture.dart';

typedef GestureCallback = void Function(Event);

typedef GetEventTarget = EventTarget Function();

typedef DispatchEvent = void Function(Event event);

typedef DispatchMouseEvent = void Function(String type, { Offset localPosition, Offset globalPosition, bool bubbles, bool cancelable });

mixin RenderPointerListenerMixin on RenderBox {
  /// Called when a pointer signal occurs over this object.
  PointerSignalEventListener? onPointerSignal;

  DispatchMouseEvent? dispatchMouseEvent;

  GestureCallback? onSwipe;

  GestureCallback? onPan;

  GestureCallback? onScale;

  GetEventTarget? getEventTarget;

  DispatchEvent? dispatchEvent;

  List<String> events = [];

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    assert(debugHandleEvent(event, entry));

    /// AddPointer when a pointer comes into contact with the screen (for touch
    /// pointers), or has its button pressed (for mouse pointers) at this widget's
    /// location.
    if (event is PointerDownEvent) {
      GestureManager.instance().addTargetToList(this);
    }
  }
}
