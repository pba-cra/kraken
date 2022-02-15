/*
 * Copyright (C) 2020-present Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show RenderObjectElement;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart'
    show RouteInformation, WidgetsBinding, WidgetsBindingObserver;
import 'package:kraken/bridge.dart';
import 'package:kraken/dom.dart';
import 'package:kraken/foundation.dart';
import 'package:kraken/gesture.dart';
import 'package:kraken/module.dart';
import 'package:kraken/rendering.dart';
import 'package:kraken/widget.dart';
import 'package:kraken/src/dom/element_registry.dart' as element_registry;


import 'bundle.dart';

const int WINDOW_ID = -1;
const int DOCUMENT_ID = -2;

// Error handler when load bundle failed.
typedef LoadHandler = void Function(Controller controller);
typedef LoadErrorHandler = void Function(FlutterError error, StackTrace stack);
typedef JSErrorHandler = void Function(String message);
typedef PendingCallback = void Function();

typedef TraverseElementCallback = void Function(Element element);

// Traverse DOM element.
void traverseElement(Element element, TraverseElementCallback callback) {
  callback(element);
  for (Element el in element.children) {
    traverseElement(el, callback);
  }
}

// See http://github.com/flutter/flutter/wiki/Desktop-shells
/// If the current platform is a desktop platform that isn't yet supported by
/// TargetPlatform, override the default platform to one that is.
/// Otherwise, do nothing.
/// No need to handle macOS, as it has now been added to TargetPlatform.
void setTargetPlatformForDesktop() {
  if (Platform.isLinux || Platform.isWindows) {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  }
}

abstract class DevToolsService {
  void init(KrakenController controller);
  void willReload();
  void didReload();
  void dispose();
}

abstract class ViewController {

  Controller rootController;

  GestureListener? gestureListener;

  Color? background;

  WidgetDelegate? widgetDelegate;

  // The methods of the KrakenNavigateDelegation help you implement custom behaviors that are triggered
  // during a kraken view's process of loading, and completing a navigation request.
  KrakenNavigationDelegate? navigationDelegate;

  late Document document;
  late Window window;

  // Hooks for DevTools.
  VoidCallback? debugDOMTreeChanged;
  void _debugDOMTreeChanged() {
    VoidCallback? f = debugDOMTreeChanged;
    if (f != null) {
      f();
    }
  }

  // Kraken have already disposed.
  bool _disposed = false;
  bool get disposed => _disposed;

  // Dispose controller and recycle all resources.
  @mustCallSuper
  void dispose() {
    // FIXME: for break circle reference
    viewport.controller = null;
    debugDOMTreeChanged = null;

    document.dispose();
    window.dispose();
    _disposed = true;
  }

  void shiftFocus(EventTarget target) {
    // TODO: get focus for other element which need to get focus.
    InputElement? inputElement = InputElement.focusInputElement;
    if (inputElement != null && inputElement != target) {
      inputElement.blur();
    }

    target.focus();
  }

  ViewController(
    viewportWidth,
    viewportHeight, {
      this.background,
      this.enableDebug = false,
      required this.rootController,
      this.navigationDelegate,
      this.widgetDelegate,
      int? contextId,
      gestureListener,
      // Viewport won't change when kraken page reload, should reuse previous page's viewportBox.
      RenderViewportBox? originalViewport
    }
  ) : _viewportWidth = viewportWidth, _viewportHeight = viewportHeight {
    if (enableDebug) {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      debugPaintSizeEnabled = true;
    }

    if (originalViewport != null) {
      // Should update to newlast controller.
      originalViewport.controller = rootController;
      viewport = originalViewport;
    } else {
      viewport = RenderViewportBox(
        background: background,
        viewportSize: Size(viewportWidth, viewportHeight),
        gestureListener: gestureListener,
        controller: rootController
      );
    }

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_CREATE_VIEWPORT_END);
      PerformanceTiming.instance().mark(PERF_ELEMENT_MANAGER_INIT_START);
    }

    element_registry.defineBuiltInElements();

    // Listeners need to be registered to window in order to dispatch events on demand.
    if (gestureListener != null) {
      if (gestureListener!.onTouchStart != null) {
        window.addEvent(EVENT_TOUCH_START);
      }

      if (gestureListener!.onTouchMove != null) {
        window.addEvent(EVENT_TOUCH_MOVE);
      }

      if (gestureListener!.onTouchEnd != null) {
        window.addEvent(EVENT_TOUCH_END);
      }
    }

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_ELEMENT_MANAGER_INIT_END);
    }
  }

  ui.WindowPadding _prevViewInsets = ui.window.viewInsets;
  late RenderViewportBox viewport;

  RenderObject getRootRenderObject() {
    return viewport;
  }

  double _viewportWidth;
  double get viewportWidth => _viewportWidth;
  set viewportWidth(double value) {
    if (value != _viewportWidth) {
      _viewportWidth = value;
      viewport.viewportSize = Size(_viewportWidth, _viewportHeight);
    }
  }

  double _viewportHeight;
  double get viewportHeight => _viewportHeight;
  set viewportHeight(double value) {
    if (value != _viewportHeight) {
      _viewportHeight = value;
      viewport.viewportSize = Size(_viewportWidth, _viewportHeight);
    }
  }

  // Enable print debug message when rendering.
  bool enableDebug;

  Future<void> handleNavigationAction(String? sourceUrl, String targetUrl,
      KrakenNavigationType navigationType) async {
    KrakenNavigationAction action =
    KrakenNavigationAction(sourceUrl, targetUrl, navigationType);

    KrakenNavigationDelegate _delegate = navigationDelegate!;

    try {
      KrakenNavigationActionPolicy policy =
      await _delegate.dispatchDecisionHandler(action);
      if (policy == KrakenNavigationActionPolicy.cancel) return;

      switch (action.navigationType) {
        case KrakenNavigationType.navigate:
          await rootController.reload(url: action.target);
          break;
        case KrakenNavigationType.reload:
          await rootController.reload(url: action.source!);
          break;
        default:
        // Navigate and other type, do nothing.
      }
    } catch (e, stack) {
      if (_delegate.errorHandler != null) {
        _delegate.errorHandler!(e, stack);
      } else {
        print('Kraken navigation failed: $e\n$stack');
      }
    }
  }
}

class HTMLViewViewController extends ViewController {
  HTMLViewViewController(
    viewportWidth,
    viewportHeight, {
      background,
      enableDebug,
      rootController,
      navigationDelegate,
      widgetDelegate
    }
  ): super(
    viewportWidth,
    viewportHeight,
    background: background,
    enableDebug: enableDebug,
    rootController: rootController,
    navigationDelegate: navigationDelegate,
    widgetDelegate: widgetDelegate,
  ) {
    document = Document(
      viewport: viewport,
      controller: rootController,
      gestureListener: gestureListener,
      widgetDelegate: widgetDelegate,
    );

    window = Window(
      document
    );
  }
}

// An Kraken View Controller designed for multiple kraken view control.
class KrakenViewController extends ViewController implements WidgetsBindingObserver, ElementsBindingObserver  {
  KrakenViewController(
    viewportWidth,
    viewportHeight, {
    background,
    enableDebug,
    int? contextId,
    required rootController,
    navigationDelegate,
    gestureListener,
    widgetDelegate,
    // Viewport won't change when kraken page reload, should reuse previous page's viewportBox.
    RenderViewportBox? originalViewport
  }): super(
    viewportWidth,
    viewportHeight,
    background: background,
    enableDebug: enableDebug,
      contextId: contextId,
      rootController: rootController,
      navigationDelegate: navigationDelegate,
      gestureListener: gestureListener,
      widgetDelegate: widgetDelegate,
      originalViewport: originalViewport
  ) {

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_VIEW_CONTROLLER_PROPERTY_INIT);
      PerformanceTiming.instance().mark(PERF_BRIDGE_INIT_START);
    }

    _contextId = contextId ?? initBridge();

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_BRIDGE_INIT_END);
      PerformanceTiming.instance().mark(PERF_CREATE_VIEWPORT_START);
    }

    document = Document(
      context: EventTargetContext(_contextId, documentNativePtrMap[_contextId]!),
      viewport: viewport,
      controller: rootController,
      gestureListener: gestureListener,
      widgetDelegate: widgetDelegate,
    );

    window = Window(
      document,
      context: EventTargetContext(_contextId, windowNativePtrMap[_contextId]!)
    );

    _setEventTarget(DOCUMENT_ID, document);
    _setEventTarget(WINDOW_ID, window);

    _setupObserver();
  }

  static double FOCUS_VIEWINSET_BOTTOM_OVERALL = 32;

  static Map<int, Pointer<NativeEventTarget>> documentNativePtrMap = {};
  static Map<int, Pointer<NativeEventTarget>> windowNativePtrMap = {};

  // Index value which identify javascript runtime context.
  late int _contextId;
  int get contextId => _contextId;

  void evaluateJavaScripts(String code, [String source = 'vm://']) {
    assert(!_disposed, 'Kraken have already disposed');
    evaluateScripts(_contextId, code, source);
  }

  void _teardownObserver() {
    if (ElementsBinding.instance != null) {
      ElementsBinding.instance!.removeObserver(this);
    } else if (WidgetsBinding.instance != null) {
      WidgetsBinding.instance!.removeObserver(this);
    }
  }

  // Attach kraken's renderObject to an renderObject.
  void attachTo(RenderObject parent, [RenderObject? previousSibling]) {
    if (parent is ContainerRenderObjectMixin) {
      parent.insert(document.renderer!, after: previousSibling);
    } else if (parent is RenderObjectWithChildMixin) {
      parent.child = document.renderer;
    }
  }

  // Dispose controller and recycle all resources.
  @override
  void dispose() {
    super.dispose();

    // FIXME: for break circle reference
    viewport.controller = null;

    debugDOMTreeChanged = null;

    _teardownObserver();

    // Should clear previous page cached ui commands
    clearUICommand(_contextId);

    disposePage(_contextId);

    _clearTargets();
    document.dispose();
    window.dispose();
    _disposed = true;
  }

  Map<int, EventTarget> _eventTargets = <int, EventTarget>{};

  T? getEventTargetById<T>(int targetId) {
    return _getEventTargetById(targetId);
  }

  int? getTargetIdByEventTarget(EventTarget eventTarget) {
    if (_eventTargets.containsValue(eventTarget)) {
      for (var entry in _eventTargets.entries) {
        if (entry.value == eventTarget) {
          return entry.key;
        }
      }
    }
    return null;
  }

  T? _getEventTargetById<T>(int targetId) {
    EventTarget? target = _eventTargets[targetId];
    if (target is T)
      return target as T;
    else
      return null;
  }

  bool _existsTarget(int id) {
    return _eventTargets.containsKey(id);
  }

  void _removeTarget(int targetId) {
    if (_eventTargets.containsKey(targetId)) {
      _eventTargets.remove(targetId);
    }
  }

  void _setEventTarget(int targetId, EventTarget target) {
    _eventTargets[targetId] = target;
  }

  void _clearTargets() {
    // Set current eventTargets to a new object, clean old targets by gc.
    _eventTargets = <int, EventTarget>{};
  }

  // export Uint8List bytes from rendered result.
  Future<Uint8List> toImage(double devicePixelRatio, [int? eventTargetId]) {
    assert(!_disposed, 'Kraken have already disposed');
    Completer<Uint8List> completer = Completer();
    try {
      if (eventTargetId != null && !_existsTarget(eventTargetId)) {
        String msg = 'toImage: unknown node id: $eventTargetId';
        completer.completeError(Exception(msg));
        return completer.future;
      }
      var node = eventTargetId == null
          ? document.documentElement
          : _getEventTargetById<EventTarget>(eventTargetId);
      if (node is Element) {
        if (!node.isRendererAttached) {
          String msg = 'toImage: the element is not attached to document tree.';
          completer.completeError(Exception(msg));
          return completer.future;
        }

        node.toBlob(devicePixelRatio: devicePixelRatio).then((Uint8List bytes) {
          completer.complete(bytes);
        }).catchError((e, stack) {
          String msg =
              'toBlob: failed to export image data from element id: $eventTargetId. error: $e}.\n$stack';
          completer.completeError(Exception(msg));
        });
      } else {
        String msg = 'toBlob: node is not an element, id: $eventTargetId';
        completer.completeError(Exception(msg));
      }
    } catch (e, stack) {
      completer.completeError(e, stack);
    }
    return completer.future;
  }

  EventTarget createElement(
      int targetId, String tagName, [EventTargetContext? eventTargetContext]) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_ELEMENT_START, uniqueId: targetId);
    }
    assert(!_existsTarget(targetId),
        'ERROR: Can not create element with same id "$targetId"');
    Element element = document.createElement(
        tagName.toUpperCase(), eventTargetContext);
    _setEventTarget(targetId, element);
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_ELEMENT_END, uniqueId: targetId);
    }

    return element;
  }

  Node createTextNode(
      int targetId, String data, [EventTargetContext? eventTargetContext]) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_TEXT_NODE_START, uniqueId: targetId);
    }
    TextNode textNode = document.createTextNode(
        data, eventTargetContext);
    _setEventTarget(targetId, textNode);
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_TEXT_NODE_END, uniqueId: targetId);
    }

    return textNode;
  }

  void createComment(int targetId, [EventTargetContext? eventTargetContext]) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_COMMENT_START, uniqueId: targetId);
    }
    Comment comment =
        document.createComment(eventTargetContext);
    _setEventTarget(targetId, comment);
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_COMMENT_END, uniqueId: targetId);
    }
  }

  void createDocumentFragment(
      int targetId, [Pointer<NativeEventTarget>? nativePtr]) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_DOCUMENT_FRAGMENT_START, uniqueId: targetId);
    }
    DocumentFragment fragment = document
        .createDocumentFragment(nativePtr == null ? null : EventTargetContext(_contextId, nativePtr));
    _setEventTarget(targetId, fragment);
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_CREATE_DOCUMENT_FRAGMENT_END, uniqueId: targetId);
    }
  }

  void addEvent(int targetId, String eventType) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_ADD_EVENT_START, uniqueId: targetId);
    }
    if (!_existsTarget(targetId)) return;
    EventTarget target = _getEventTargetById<EventTarget>(targetId)!;

    if (target is Element) {
      target.addEvent(eventType);
    } else if (target is Window) {
      target.addEvent(eventType);
    } else if (target is Document) {
      target.addEvent(eventType);
    }

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_ADD_EVENT_END, uniqueId: targetId);
    }
  }

  void removeEvent(int targetId, String eventType) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_REMOVE_EVENT_START, uniqueId: targetId);
    }
    assert(_existsTarget(targetId), 'targetId: $targetId event: $eventType');

    Element target = _getEventTargetById<Element>(targetId)!;

    target.removeEvent(eventType);
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_REMOVE_EVENT_END, uniqueId: targetId);
    }
  }

  void cloneNode(int originalId, int newId) {
    EventTarget originalTarget = _getEventTargetById(originalId)!;
    EventTarget newTarget = _getEventTargetById(newId)!;

    // Current only element clone will process in dart.
    if (originalTarget is Element) {
      Element newElement = newTarget as Element;
      // Copy inline style.
      originalTarget.inlineStyle.forEach((key, value) {
        newElement.setInlineStyle(key, value);
      });
      // Copy element attributes.
      originalTarget.properties.forEach((key, value) {
        newElement.setProperty(key, value);
      });
    }
  }

  void removeNode(int targetId) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_REMOVE_NODE_START, uniqueId: targetId);
    }

    assert(_existsTarget(targetId), 'targetId: $targetId');

    Node target = _getEventTargetById<Node>(targetId)!;
    target.parentNode?.removeChild(target);

    _debugDOMTreeChanged();

    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_REMOVE_NODE_END, uniqueId: targetId);
    }
  }

  /// <!-- beforebegin -->
  /// <p>
  ///   <!-- afterbegin -->
  ///   foo
  ///   <!-- beforeend -->
  /// </p>
  /// <!-- afterend -->
  void insertAdjacentNode(int targetId, String position, int newTargetId) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_INSERT_ADJACENT_NODE_START, uniqueId: targetId);
    }

    assert(_existsTarget(targetId),
        'targetId: $targetId position: $position newTargetId: $newTargetId');
    assert(_existsTarget(newTargetId),
        'newTargetId: $newTargetId position: $position');

    Node target = _getEventTargetById<Node>(targetId)!;
    Node newNode = _getEventTargetById<Node>(newTargetId)!;
    Node? targetParentNode = target.parentNode;

    switch (position) {
      case 'beforebegin':
        targetParentNode!.insertBefore(newNode, target);
        break;
      case 'afterbegin':
        target.insertBefore(newNode, target.firstChild);
        break;
      case 'beforeend':
        target.appendChild(newNode);
        break;
      case 'afterend':
        if (targetParentNode!.lastChild == target) {
          targetParentNode.appendChild(newNode);
        } else {
          targetParentNode.insertBefore(
            newNode,
            targetParentNode
                .childNodes[targetParentNode.childNodes.indexOf(target) + 1],
          );
        }
        break;
    }

    _debugDOMTreeChanged();

    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_INSERT_ADJACENT_NODE_END, uniqueId: targetId);
    }
  }

  void setProperty(int targetId, String key, dynamic value) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_SET_PROPERTIES_START, uniqueId: targetId);
    }

    assert(
        _existsTarget(targetId), 'targetId: $targetId key: $key value: $value');
    Node target = _getEventTargetById<Node>(targetId)!;

    if (target is Element) {
      // Only Element has properties.
      target.setProperty(key, value);
    } else if (target is TextNode && key == 'data' || key == 'nodeValue') {
      (target as TextNode).data = value;
    } else {
      debugPrint(
          'Only element has properties, try setting $key to Node(#$targetId).');
    }

    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_SET_PROPERTIES_END, uniqueId: targetId);
    }
  }

  dynamic getProperty(int targetId, String key) {
    assert(_existsTarget(targetId), 'targetId: $targetId key: $key');
    Node target = _getEventTargetById<Node>(targetId)!;

    if (target is Element) {
      // Only Element has properties
      return target.getProperty(key);
    } else if (target is TextNode && key == 'data' || key == 'nodeValue') {
      return (target as TextNode).data;
    } else {
      return null;
    }
  }

  void removeProperty(int targetId, String key) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_SET_PROPERTIES_START, uniqueId: targetId);
    }
    assert(_existsTarget(targetId), 'targetId: $targetId key: $key');
    Node target = _getEventTargetById<Node>(targetId)!;

    if (target is Element) {
      target.removeProperty(key);
    } else if (target is TextNode && key == 'data' || key == 'nodeValue') {
      (target as TextNode).data = '';
    } else {
      debugPrint(
          'Only element has properties, try removing $key from Node(#$targetId).');
    }
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_SET_PROPERTIES_END, uniqueId: targetId);
    }
  }

  void setInlineStyle(int targetId, String key, String value) {
    if (kProfileMode) {
      PerformanceTiming.instance()
          .mark(PERF_SET_STYLE_START, uniqueId: targetId);
    }
    assert(_existsTarget(targetId), 'id: $targetId key: $key value: $value');
    Node? target = _getEventTargetById<Node>(targetId);
    if (target == null) return;

    if (target is Element) {
      target.setInlineStyle(key, value);
    } else {
      debugPrint(
          'Only element has style, try setting style.$key from Node(#$targetId).');
    }
    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_SET_STYLE_END, uniqueId: targetId);
    }
  }

  void flushPendingStyleProperties(int targetId) {
    if (!_existsTarget(targetId)) return;
    Node? target = _getEventTargetById<Node>(targetId);
    if (target == null) return;

    if (target is Element) {
      target.style.flushPendingProperties();
    } else {
      debugPrint(
          'Only element has style, try flushPendingStyleProperties from Node(#$targetId).');
    }
  }

  // Call from JS Bridge before JS side eventTarget object been Garbage collected.
  void disposeEventTarget(int targetId) {
    Node? target = _getEventTargetById<Node>(targetId);
    if (target == null) return;

    _removeTarget(targetId);
    target.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    // TODO: implement didChangeAccessibilityFeatures
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // TODO: implement didChangeAppLifecycleState
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // TODO: implement didChangeLocales
  }

  @override
  void didChangeMetrics() {
    double bottomInset =
        ui.window.viewInsets.bottom / ui.window.devicePixelRatio;
    if (_prevViewInsets.bottom > ui.window.viewInsets.bottom) {
      // Hide keyboard
      viewport.bottomInset = bottomInset;
    } else {
      bool shouldScrollByToCenter = false;
      InputElement? focusInputElement = InputElement.focusInputElement;
      if (focusInputElement != null) {
        RenderBox? renderer = focusInputElement.renderer;
        if (renderer != null && renderer.hasSize) {
          Offset focusOffset = renderer.localToGlobal(Offset.zero);
          // FOCUS_VIEWINSET_BOTTOM_OVERALL to meet border case.
          if (focusOffset.dy >
              viewportHeight - bottomInset - FOCUS_VIEWINSET_BOTTOM_OVERALL) {
            shouldScrollByToCenter = true;
          }
        }
      }
      // Show keyboard
      viewport.bottomInset = bottomInset;
      if (shouldScrollByToCenter) {
        SchedulerBinding.instance!.addPostFrameCallback((_) {
          window.scrollBy(0, bottomInset);
        });
      }
    }
    _prevViewInsets = ui.window.viewInsets;
  }

  @override
  void didChangePlatformBrightness() {
    // TODO: implement didChangePlatformBrightness
  }

  @override
  void didChangeTextScaleFactor() {
    // TODO: implement didChangeTextScaleFactor
  }

  @override
  void didHaveMemoryPressure() {
    // TODO: implement didHaveMemoryPressure
  }

  @override
  Future<bool> didPopRoute() async {
    // TODO: implement didPopRoute
    return false;
  }

  @override
  Future<bool> didPushRoute(String route) async {
    // TODO: implement didPushRoute
    return false;
  }

  @override
  Future<bool> didPushRouteInformation(
      RouteInformation routeInformation) async {
    // TODO: implement didPushRouteInformation
    return false;
  }

  void _setupObserver() {
    if (ElementsBinding.instance != null) {
      ElementsBinding.instance!.addObserver(this);
    } else if (WidgetsBinding.instance != null) {
      WidgetsBinding.instance!.addObserver(this);
    }
  }
}

// An controller designed to control kraken's functional modules.
class KrakenModuleController with TimerMixin, ScheduleFrameMixin {
  late ModuleManager _moduleManager;
  ModuleManager get moduleManager => _moduleManager;

  KrakenModuleController(KrakenController controller, int contextId) {
    _moduleManager = ModuleManager(controller, contextId);
  }

  void dispose() {
    disposeTimer();
    disposeScheduleFrame();
    _moduleManager.dispose();
  }
}


abstract class Controller {
  String? _name;
  String? get name => _name;

  @mustCallSuper
  set name(String? value) {
    if (value == null) return;
    _name = value;
  }

  WidgetDelegate? widgetDelegate;

  UriParser? uriParser;

  final DevToolsService? devToolsService;
  final GestureListener? gestureListener;

  late RenderObjectElement rootFlutterElement;

  late ViewController _view;

  ViewController get view {
    return _view;
  }

  late KrakenModuleController _module;

  KrakenModuleController get module {
    return _module;
  }

  KrakenBundle? bundle;

  LoadHandler? onLoad;

  // Error handler when load bundle failed.
  LoadErrorHandler? onLoadError;

  @mustCallSuper
  void dispose() {
    _view.dispose();

    if (devToolsService != null) {
      devToolsService!.dispose();
    }
  }

  void dispatchEvent(Event event) {
    EventTarget? target = event.target;
    if (event.type == EVENT_CLICK && target != null) {
      _view.shiftFocus(target);
    }
  }

  final Queue<HistoryItem> previousHistoryStack = Queue();
  final Queue<HistoryItem> nextHistoryStack = Queue();

  Uri get referrer {
    if (bundle is NetworkBundle) {
      return Uri.parse(href);
    } else if (bundle is AssetsBundle) {
      return Directory(href).uri;
    } else {
      return fallbackBundleUri(hashCode);
    }
  }

  static Uri fallbackBundleUri([int? id]) {
    // The fallback origin uri, like `vm://bundle/0`
    return Uri(scheme: 'vm', host: 'bundle', path: id != null ? '$id' : null);
  }

  void setNavigationDelegate(KrakenNavigationDelegate delegate) {
    _view.navigationDelegate = delegate;
  }

  @mustCallSuper
  Future<void> unload() async {
    assert(!view._disposed, 'Kraken have already disposed');

    // Wait for next microtask to make sure C++ native Elements are GC collected.
    Completer completer = Completer();
    Future.microtask(() {
      _module.dispose();
      view.dispose();

      // _view = KrakenViewController(view.viewportWidth, view.viewportHeight,
      //     background: view.background,
      //     enableDebug: view.enableDebug,
      //     contextId: view.contextId,
      //     rootController: this,
      //     navigationDelegate: view.navigationDelegate,
      //     gestureListener: view.gestureListener,
      //     widgetDelegate: view.widgetDelegate,
      //     originalViewport: view.viewport
      // );
      //
      // _module = KrakenModuleController(this, view.contextId);

      completer.complete();
    });

    return completer.future;
  }

  String get origin => Uri.parse(href).origin;

  KrakenMethodChannel? _methodChannel;

  KrakenMethodChannel? get methodChannel => _methodChannel;

  // If bundle not configured at dart side, url can be obtained from env or native side.
  Future<KrakenBundle?> get getDefaultBundle async {
    String? envUrl = (getBundleURLFromEnv() ?? getBundlePathFromEnv());
    // Load url from native side (Java,Objective-C).
    if (envUrl == null && methodChannel is KrakenNativeChannel) {
      envUrl = await (methodChannel as KrakenNativeChannel).getUrl();
    }
    if (envUrl != null) {
      bundle = KrakenBundle.fromUrl(envUrl);
    }
  }

  // preload javascript source and cache it.
  Future<void> loadBundle(KrakenBundle bundle) async {
    assert(!view._disposed, 'Kraken have already disposed');

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_JS_BUNDLE_LOAD_START);
    }

    if (bundle.src.isEmpty && bundle.content == null && bundle.bytecode == null) {
      // Do nothing if bundle is empty.
      return;
    }

    // Load bundle need push curret href to history.
    _addHistory(bundle);
    this.bundle = bundle;

    if (onLoadError != null) {
      try {
        await bundle.resolve(this);
      } catch (e, stack) {
        onLoadError!(FlutterError(e.toString()), stack);
      }
    } else {
      await bundle.resolve(this);
    }

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_JS_BUNDLE_LOAD_END);
    }
  }

  // execute preloaded javascript source
  Future<void> evalBundle() async {
    assert(!_view._disposed, 'Kraken have already disposed');
    if (bundle != null) {
      await bundle!.eval(this);
      // trigger DOMContentLoaded event
      module.requestAnimationFrame((_) {
        Event event = Event(EVENT_DOM_CONTENT_LOADED);
        EventTarget window = view.window;
        window.dispatchEvent(event);
        // @HACK: window.load should trigger after all image had loaded.
        // Someone needs to fix this in the future.
        module.requestAnimationFrame((_) {
          Event event = Event(EVENT_LOAD);
          window.dispatchEvent(event);
        });
      });

      if (onLoad != null) {
        // DOM element are created at next frame, so we should trigger onload callback in the next frame.
        module.requestAnimationFrame((_) {
          onLoad!(this);
        });
      }
    }
  }

  String get href {
    HistoryModule historyModule =
    module.moduleManager.getModule<HistoryModule>('History')!;
    return historyModule.href;
  }

  set href(String value) {
    _addHistory(KrakenBundle.fromUrl(value));
  }

  _addHistory(KrakenBundle bundle) {
    HistoryModule historyModule =
    module.moduleManager.getModule<HistoryModule>('History')!;
    historyModule.bundle = bundle;
  }

  @mustCallSuper
  // reload current kraken view.
  Future<void> reload({String? url}) async {
    assert(!view._disposed, 'Kraken have already disposed');

    if (devToolsService != null) {
      devToolsService!.willReload();
    }

    await unload();
    await loadBundle(KrakenBundle.fromUrl(url ?? href));
    await evalBundle();

    if (devToolsService != null) {
      devToolsService!.didReload();
    }
  }

  Controller(
    String? name, {
      this.uriParser,
      this.devToolsService,
      this.gestureListener,
      this.widgetDelegate,
      this.bundle,
      this.onLoad,
      this.onLoadError
    }
  )  : _name = name {
    uriParser ??= UriParser();

    // TODO: support devTools for HTMLView.
    // if (devToolsService != null) {
    //   devToolsService!.init(this);
    // }
  }
}

class HTMLViewController extends Controller {
  @override
  HTMLViewViewController get view {
    return _view as HTMLViewViewController;
  }

  HTMLViewController(
      String? name,
      double viewportWidth,
      double viewportHeight, {
        bool showPerformanceOverlay = false,
        enableDebug = false,
        Color? background,
        GestureListener? gestureListener,
        KrakenNavigationDelegate? navigationDelegate,
        WidgetDelegate? widgetDelegate,
        final DevToolsService? devToolsService,
        UriParser? uriParser
      }) : super(name, uriParser: uriParser, widgetDelegate: widgetDelegate, devToolsService: devToolsService) {
    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_CONTROLLER_PROPERTY_INIT);
      PerformanceTiming.instance().mark(PERF_VIEW_CONTROLLER_INIT_START);
    }

    _view = HTMLViewViewController(
      viewportWidth,
      viewportHeight,
      background: background,
      enableDebug: enableDebug,
      rootController: this,
      navigationDelegate: navigationDelegate ?? KrakenNavigationDelegate(),
      widgetDelegate: widgetDelegate,
    );

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_VIEW_CONTROLLER_INIT_END);
    }
  }
}

class KrakenController extends Controller {
  @override
  set name(String? value) {
    super.name = value;
    if (value == null) return;
    if (_name != null) {
      int? contextId = _nameIdMap[_name];
      _nameIdMap.remove(_name);
      _nameIdMap[value] = contextId!;
    }
    _name = value;
  }

  // Error handler when got javascript error when evaluate javascript codes.
  JSErrorHandler? onJSError;

  final HttpClientInterceptor? httpClientInterceptor;

  static final Map<String, int> _nameIdMap = {};
  static final SplayTreeMap<int, KrakenController?> _controllerMap = SplayTreeMap();

  static KrakenController? getControllerOfJSContextId(int? contextId) {
    if (!_controllerMap.containsKey(contextId)) {
      return null;
    }

    return _controllerMap[contextId];
  }

  static SplayTreeMap<int, KrakenController?> getControllerMap() {
    return _controllerMap;
  }

  static KrakenController? getControllerOfName(String name) {
    if (!_nameIdMap.containsKey(name)) return null;
    int? contextId = _nameIdMap[name];
    return getControllerOfJSContextId(contextId);
  }

  @override
  KrakenViewController get view {
    return _view as KrakenViewController;
  }

  @override
  Future<void> unload() async {
    super.unload();
    // Should clear previous page cached ui commands
    clearUICommand(view.contextId);

    allocateNewPage(view.contextId);
  }

  KrakenController(
    String? name,
    double viewportWidth,
    double viewportHeight, {
    bool showPerformanceOverlay = false,
    enableDebug = false,
    Color? background,
    GestureListener? gestureListener,
    KrakenNavigationDelegate? navigationDelegate,
    KrakenMethodChannel? methodChannel,
    WidgetDelegate? widgetDelegate,
    KrakenBundle? bundle,
    LoadHandler? onLoad,
    LoadErrorHandler? onLoadError,
    this.onJSError,
    this.httpClientInterceptor,
    final DevToolsService? devToolsService,
    UriParser? uriParser,
  }) : super(name, bundle: bundle, onLoad: onLoad, onLoadError: onLoadError, uriParser: uriParser, devToolsService: devToolsService, widgetDelegate: widgetDelegate) {
    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_CONTROLLER_PROPERTY_INIT);
      PerformanceTiming.instance().mark(PERF_VIEW_CONTROLLER_INIT_START);
    }

    _methodChannel = methodChannel;
    KrakenMethodChannel.setJSMethodCallCallback(this);

    _view = KrakenViewController(
      viewportWidth,
      viewportHeight,
      background: background,
      enableDebug: enableDebug,
      rootController: this,
      navigationDelegate: navigationDelegate ?? KrakenNavigationDelegate(),
      gestureListener: gestureListener,
      widgetDelegate: widgetDelegate,
    );

    if (kProfileMode) {
      PerformanceTiming.instance().mark(PERF_VIEW_CONTROLLER_INIT_END);
    }

    final int contextId = view.contextId;

    _module = KrakenModuleController(this, contextId);

    if (bundle != null) {
      HistoryModule historyModule =
          module.moduleManager.getModule<HistoryModule>('History')!;
      historyModule.bundle = bundle;
    }

    assert(!_controllerMap.containsKey(contextId),
        'found exist contextId of KrakenController, contextId: $contextId');
    _controllerMap[contextId] = this;
    assert(!_nameIdMap.containsKey(name),
        'found exist name of KrakenController, name: $name');
    if (name != null) {
      _nameIdMap[name] = contextId;
    }

    setupHttpOverrides(httpClientInterceptor, contextId: contextId);

    if (devToolsService != null) {
      devToolsService.init(this);
    }
  }

  bool _paused = false;
  bool get paused => _paused;

  final List<PendingCallback> _pendingCallbacks = [];

  void pushPendingCallbacks(PendingCallback callback) {
    _pendingCallbacks.add(callback);
  }

  void flushPendingCallbacks() {
    for (int i = 0; i < _pendingCallbacks.length; i++) {
      _pendingCallbacks[i]();
    }
    _pendingCallbacks.clear();
  }

  // Pause all timers and callbacks if kraken page are invisible.
  void pause() {
    _paused = true;
    module.pauseInterval();
  }

  // Resume all timers and callbacks if kraken page now visible.
  void resume() {
    _paused = false;
    flushPendingCallbacks();
    module.resumeInterval();
  }

  @override
  void dispose() {
    super.dispose();
    view.dispose();
    _module.dispose();
    _controllerMap[view.contextId] = null;
    _controllerMap.remove(view.contextId);
    _nameIdMap.remove(name);

    if (devToolsService != null) {
      devToolsService!.dispose();
    }
  }

  @deprecated
  String? get bundlePath => href;

  @deprecated
  set bundlePath(String? value) {
    if (value == null) return;
    // Set bundlePath should set the path to history module.
    href = value;
  }

  @deprecated
  String? get bundleURL => href;

  @deprecated
  set bundleURL(String? value) {
    if (value == null) return;
    // Set bundleURL should set the url to history module.
    href = value;
  }
}

mixin RenderObjectWithControllerMixin {
  // Kraken controller reference which control all kraken created renderObjects.
  Controller? controller;
}
