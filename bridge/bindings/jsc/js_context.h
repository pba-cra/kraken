/*
 * Copyright (C) 2020 Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

#ifndef KRAKENBRIDGE_JS_CONTEXT_H
#define KRAKENBRIDGE_JS_CONTEXT_H

#include "foundation/js_engine_adaptor.h"
#include <JavaScriptCore/JavaScript.h>
#include <deque>
#include <map>
#include <string>

#ifndef __has_builtin
#define __has_builtin(x) 0
#endif

#if __has_builtin(__builtin_expect) || defined(__GNUC__)
#define JSC_LIKELY(EXPR) __builtin_expect((bool)(EXPR), true)
#define JSC_UNLIKELY(EXPR) __builtin_expect((bool)(EXPR), false)
#else
#define JSC_LIKELY(EXPR) (EXPR)
#define JSC_UNLIKELY(EXPR) (EXPR)
#endif

namespace kraken::binding::jsc {

class JSContext {
public:
  JSContext() = delete;
  JSContext(int32_t contextId, const JSExceptionHandler &handler, void *owner);
  ~JSContext();

  void evaluateJavaScript(const uint16_t *code, size_t codeLength, const char *sourceURL, int startLine);
  void evaluateJavaScript(const char *code, const char *sourceURL, int startLine);

  bool isValid();

  JSObjectRef global();
  JSGlobalContextRef context();

  int32_t getContextId();

  void *getOwner();

  bool handleException(JSValueRef exc);

  void emplaceGlobalString(JSStringRef string) {
    globalStrings.emplace_back(string);
  }

private:
  void releaseGlobalString();

  int32_t contextId;
  JSExceptionHandler _handler;
  void *owner;
  std::atomic<bool> ctxInvalid_{false};
  JSGlobalContextRef ctx_;
  std::deque<JSStringRef> globalStrings;
};

typedef JSValueRef (*KrakenJSObjectCallAsFunctionCallback)(std::unique_ptr<JSContext> context, JSObjectRef function,
                                                           JSObjectRef thisObject, size_t argumentCount,
                                                           const JSValueRef arguments[], JSValueRef *exception);

class HostObject {
public:
  static JSValueRef proxyGetProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName,
                                     JSValueRef *exception);
  static bool proxySetProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value,
                               JSValueRef *exception);
  static void proxyGetPropertyNames(JSContextRef ctx, JSObjectRef object, JSPropertyNameAccumulatorRef propertyNames);
  static void finalize(JSObjectRef obj);

  HostObject() = delete;
  HostObject(std::unique_ptr<JSContext> &context, const char *name);

  std::unique_ptr<JSContext> &context;
  JSClassRef object;
  // The C++ object's dtor will be called when the GC finalizes this
  // object.  (This may be as late as when the JSContext is shut down.)
  // You have no control over which thread it is called on.  This will
  // be called from inside the GC, so it is unsafe to do any VM
  // operations which require a JSContext&.  Derived classes' dtors
  // should also avoid doing anything expensive.  Calling the dtor on
  // a js object is explicitly ok.  If you want to do JS operations,
  // or any nontrivial work, you should add it to a work queue, and
  // manage it externally.
  virtual ~HostObject();

  // When JS wants a property with a given name from the HostObject,
  // it will call this method.  If it throws an exception, the call
  // will throw a JS \c Error object. By default this returns undefined.
  // \return the value for the property.
  virtual JSValueRef getProperty(JSStringRef name, JSValueRef *exception);

  // When JS wants to set a property with a given name on the HostObject,
  // it will call this method. If it throws an exception, the call will
  // throw a JS \c Error object. By default this throws a type error exception
  // mimicking the behavior of a frozen object in strict mode.
  virtual void setProperty(JSStringRef name, JSValueRef value, JSValueRef *exception);

  virtual void getPropertyNames(JSPropertyNameAccumulatorRef accumulator);
};

std::string JSStringToStdString(JSStringRef jsString);

std::unique_ptr<JSContext> createJSContext(int32_t contextId, const JSExceptionHandler &handler, void *owner);

} // namespace kraken::binding::jsc

#endif // KRAKENBRIDGE_JS_CONTEXT_H
