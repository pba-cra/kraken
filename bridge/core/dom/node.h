/*
 * Copyright (C) 2021-present The Kraken authors. All rights reserved.
 */

#ifndef KRAKENBRIDGE_NODE_H
#define KRAKENBRIDGE_NODE_H

#include <set>
#include <utility>

#include "events/event_target.h"
#include "foundation/macros.h"
#include "tree_scope.h"

namespace kraken {

const int kDOMNodeTypeShift = 2;
const int kElementNamespaceTypeShift = 4;
const int kNodeStyleChangeShift = 15;
const int kNodeCustomElementShift = 17;

class Element;
class Document;
class DocumentFragment;
class ContainerNode;
class NodeData;
class NodeList;

enum class CustomElementState : uint32_t {
  // https://dom.spec.whatwg.org/#concept-element-custom-element-state
  kUncustomized = 0,
  kCustom = 1 << kNodeCustomElementShift,
  kPreCustomized = 2 << kNodeCustomElementShift,
  kUndefined = 3 << kNodeCustomElementShift,
  kFailed = 4 << kNodeCustomElementShift,
};

enum class CloneChildrenFlag { kSkip, kClone, kCloneWithShadows };

// A Node is a base class for all objects in the DOM tree.
// The spec governing this interface can be found here:
// https://dom.spec.whatwg.org/#interface-node
class Node : public EventTarget {
  DEFINE_WRAPPERTYPEINFO();
  friend class TreeScope;

 public:
  enum NodeType {
    kElementNode = 1,
    kAttributeNode = 2,
    kTextNode = 3,
    kCommentNode = 8,
    kDocumentNode = 9,
    kDocumentTypeNode = 10,
    kDocumentFragmentNode = 11,
  };

  using ImplType = Node*;
  static Node* Create(ExecutingContext* context, ExceptionState& exception_state);

  // DOM methods & attributes for Node
  bool HasTagName(const AtomicString&) const;
  virtual std::string nodeName() const = 0;
  virtual std::string nodeValue() const;
  virtual void setNodeValue(const AtomicString&);
  virtual NodeType nodeType() const = 0;

  ContainerNode* parentNode() const;
  Element* parentElement() const;
  Node* previousSibling() const { return previous_; }
  Node* nextSibling() const { return next_; }
  NodeList* childNodes();
  Node* firstChild() const;
  Node* lastChild() const;
  Node& TreeRoot() const;
  void remove(ExceptionState&);

  Node* insertBefore(Node* new_child, Node* ref_child, ExceptionState&);
  Node* replaceChild(Node* new_child, Node* old_child, ExceptionState&);
  Node* removeChild(Node* child, ExceptionState&);
  Node* appendChild(Node* new_child, ExceptionState&);

  bool hasChildren() const { return firstChild(); }
  Node* cloneNode(bool deep, ExceptionState&) const;
  Node* cloneNode(ExceptionState&) const;

  // https://dom.spec.whatwg.org/#concept-node-clone
  virtual Node* Clone(Document&, CloneChildrenFlag) const = 0;

  bool isEqualNode(Node*, ExceptionState& exception_state) const;
  bool isEqualNode(Node*) const;
  bool isSameNode(const Node* other, ExceptionState& exception_state) const { return this == other; }

  AtomicString textContent(bool convert_brs_to_newlines = false) const;
  virtual void setTextContent(const AtomicString&);

  // Other methods (not part of DOM)
  FORCE_INLINE bool IsTextNode() const { return GetDOMNodeType() == DOMNodeType::kText; }
  FORCE_INLINE bool IsContainerNode() const { return GetFlag(kIsContainerFlag); }
  FORCE_INLINE bool IsElementNode() const { return GetDOMNodeType() == DOMNodeType::kElement; }
  FORCE_INLINE bool IsDocumentFragment() const { return GetDOMNodeType() == DOMNodeType::kDocumentFragment; }

  FORCE_INLINE bool IsHTMLElement() const { return GetElementNamespaceType() == ElementNamespaceType::kHTML; }
  FORCE_INLINE bool IsMathMLElement() const { return GetElementNamespaceType() == ElementNamespaceType::kMathML; }
  FORCE_INLINE bool IsSVGElement() const { return GetElementNamespaceType() == ElementNamespaceType::kSVG; }

  CustomElementState GetCustomElementState() const {
    return static_cast<CustomElementState>(node_flags_ & kCustomElementStateMask);
  }
  bool IsCustomElement() const { return GetCustomElementState() != CustomElementState::kUncustomized; }
  void SetCustomElementState(CustomElementState);

  virtual bool IsMediaElement() const { return false; }
  virtual bool IsAttributeNode() const { return false; }
  virtual bool IsCharacterDataNode() const { return false; }

  // StyledElements allow inline style (style="border: 1px"), presentational
  // attributes (ex. color), class names (ex. class="foo bar") and other
  // non-basic styling features. They also control if this element can
  // participate in style sharing.
  bool IsStyledElement() const { return IsHTMLElement() || IsSVGElement() || IsMathMLElement(); }

  bool IsDocumentNode() const;

  // Node's parent, shadow tree host.
  ContainerNode* ParentOrShadowHostNode() const;
  Element* ParentOrShadowHostElement() const;
  void SetParentOrShadowHostNode(ContainerNode*);

  // ---------------------------------------------------------------------------
  // Notification of document structure changes (see container_node.h for more
  // notification methods)
  //
  // InsertedInto() implementations must not modify the DOM tree, and must not
  // dispatch synchronous events.
  virtual void InsertedInto(ContainerNode& insertion_point);

  // Notifies the node that it is no longer part of the tree.
  //
  // This is a dual of InsertedInto(), but does not require the overhead of
  // event dispatching, and is called _after_ the node is removed from the tree.
  //
  // RemovedFrom() implementations must not modify the DOM tree, and must not
  // dispatch synchronous events.
  virtual void RemovedFrom(ContainerNode& insertion_point);

  // Knows about all kinds of hosts.
  ContainerNode* ParentOrShadowHostOrTemplateHostNode() const;

  // Returns the parent node, but nullptr if the parent node is a ShadowRoot.
  ContainerNode* NonShadowBoundaryParentNode() const;

  // These low-level calls give the caller responsibility for maintaining the
  // integrity of the tree.
  void SetPreviousSibling(Node* previous) { previous_ = previous; }
  void SetNextSibling(Node* next) { next_ = next; }

  bool HasEventTargetData() const { return GetFlag(kHasEventTargetDataFlag); }
  void SetHasEventTargetData(bool flag) { SetFlag(flag, kHasEventTargetDataFlag); }

  unsigned NodeIndex() const;

  // Returns the DOM ownerDocument attribute. This method never returns null,
  // except in the case of a Document node.
  Document* ownerDocument() const;

  // Returns the document associated with this node. A Document node returns
  // itself.
  Document& GetDocument() const { return GetTreeScope().GetDocument(); }

  TreeScope& GetTreeScope() const {
    assert(tree_scope_);
    return *tree_scope_;
  };

  // Returns true if this node is connected to a document, false otherwise.
  // See https://dom.spec.whatwg.org/#connected for the definition.
  bool isConnected() const { return GetFlag(kIsConnectedFlag); }

  bool IsInDocumentTree() const { return isConnected(); }
  bool IsInTreeScope() const { return GetFlag(static_cast<NodeFlags>(kIsConnectedFlag)); }

  bool IsDocumentTypeNode() const { return nodeType() == kDocumentTypeNode; }
  virtual bool ChildTypeAllowed(NodeType) const { return false; }
  unsigned CountChildren() const;

  bool IsDescendantOf(const Node*) const;
  bool contains(const Node*, ExceptionState&) const;
  bool ContainsIncludingHostElements(const Node&) const;
  Node* CommonAncestor(const Node&, ContainerNode* (*parent)(const Node&)) const;

  enum ShadowTreesTreatment { kTreatShadowTreesAsDisconnected, kTreatShadowTreesAsComposed };

  EventTargetData* GetEventTargetData() override;
  EventTargetData& EnsureEventTargetData() override;

  bool IsFinishedParsingChildren() const { return GetFlag(kIsFinishedParsingChildrenFlag); }

  void SetHasDuplicateAttributes() { SetFlag(kHasDuplicateAttributes); }
  bool HasDuplicateAttribute() const { return GetFlag(kHasDuplicateAttributes); }

  bool SelfOrAncestorHasDirAutoAttribute() const { return GetFlag(kSelfOrAncestorHasDirAutoAttribute); }
  void SetSelfOrAncestorHasDirAutoAttribute() { SetFlag(kSelfOrAncestorHasDirAutoAttribute); }
  void ClearSelfOrAncestorHasDirAutoAttribute() { ClearFlag(kSelfOrAncestorHasDirAutoAttribute); }

  NodeData& CreateData();
  bool HasData() const { return GetFlag(kHasDataFlag); }
  // |RareData| cannot be replaced or removed once assigned.
  NodeData* Data() const { return data_.get(); }
  NodeData& EnsureData();

  void Trace(GCVisitor*) const override;

 private:
  enum NodeFlags : uint32_t {
    kHasDataFlag = 1,

    // Node type flags. These never change once created.
    kIsContainerFlag = 1 << 1,
    kDOMNodeTypeMask = 0x3 << kDOMNodeTypeShift,
    kElementNamespaceTypeMask = 0x3 << kElementNamespaceTypeShift,

    // Tree state flags. These change when the element is added/removed
    // from a DOM tree.
    kIsConnectedFlag = 1 << 8,

    // Set by the parser when the children are done parsing.
    kIsFinishedParsingChildrenFlag = 1 << 10,

    kCustomElementStateMask = 0x7 << kNodeCustomElementShift,
    kHasNameOrIsEditingTextFlag = 1 << 20,
    kHasEventTargetDataFlag = 1 << 21,

    kHasDuplicateAttributes = 1 << 24,

    kSelfOrAncestorHasDirAutoAttribute = 1 << 27,
    kDefaultNodeFlags = kIsFinishedParsingChildrenFlag,
    // 2 bits remaining.
  };

  FORCE_INLINE bool GetFlag(NodeFlags mask) const { return node_flags_ & mask; }
  void SetFlag(bool f, NodeFlags mask) { node_flags_ = (node_flags_ & ~mask) | (-(int32_t)f & mask); }
  void SetFlag(NodeFlags mask) { node_flags_ |= mask; }
  void ClearFlag(NodeFlags mask) { node_flags_ &= ~mask; }

  enum class DOMNodeType : uint32_t {
    kElement = 0,
    kText = 1 << kDOMNodeTypeShift,
    kDocumentFragment = 2 << kDOMNodeTypeShift,
    kOther = 3 << kDOMNodeTypeShift,
  };

  FORCE_INLINE DOMNodeType GetDOMNodeType() const { return static_cast<DOMNodeType>(node_flags_ & kDOMNodeTypeMask); }

  enum class ElementNamespaceType : uint32_t {
    kHTML = 0,
    kMathML = 1 << kElementNamespaceTypeShift,
    kSVG = 2 << kElementNamespaceTypeShift,
    kOther = 3 << kElementNamespaceTypeShift,
  };
  FORCE_INLINE ElementNamespaceType GetElementNamespaceType() const {
    return static_cast<ElementNamespaceType>(node_flags_ & kElementNamespaceTypeMask);
  }

 protected:
  enum ConstructionType {
    kCreateOther = kDefaultNodeFlags | static_cast<NodeFlags>(DOMNodeType::kOther) |
                   static_cast<NodeFlags>(ElementNamespaceType::kOther),
    kCreateText = kDefaultNodeFlags | static_cast<NodeFlags>(DOMNodeType::kText) |
                  static_cast<NodeFlags>(ElementNamespaceType::kOther),
    kCreateContainer = kDefaultNodeFlags | kIsContainerFlag | static_cast<NodeFlags>(DOMNodeType::kOther) |
                       static_cast<NodeFlags>(ElementNamespaceType::kOther),
    kCreateElement = kDefaultNodeFlags | kIsContainerFlag | static_cast<NodeFlags>(DOMNodeType::kElement) |
                     static_cast<NodeFlags>(ElementNamespaceType::kOther),
    kCreateDocumentFragment = kDefaultNodeFlags | kIsContainerFlag |
                              static_cast<NodeFlags>(DOMNodeType::kDocumentFragment) |
                              static_cast<NodeFlags>(ElementNamespaceType::kOther),
    kCreateHTMLElement = kDefaultNodeFlags | kIsContainerFlag | static_cast<NodeFlags>(DOMNodeType::kElement) |
                         static_cast<NodeFlags>(ElementNamespaceType::kHTML),
    kCreateMathMLElement = kDefaultNodeFlags | kIsContainerFlag | static_cast<NodeFlags>(DOMNodeType::kElement) |
                           static_cast<NodeFlags>(ElementNamespaceType::kMathML),
    kCreateSVGElement = kDefaultNodeFlags | kIsContainerFlag | static_cast<NodeFlags>(DOMNodeType::kElement) |
                        static_cast<NodeFlags>(ElementNamespaceType::kSVG),
    kCreateDocument = kCreateContainer | kIsConnectedFlag,
  };

  void SetTreeScope(TreeScope* scope) { tree_scope_ = scope; }

  Node(Document*, ConstructionType);

 private:
  uint32_t node_flags_;
  Node* parent_or_shadow_host_node_;
  Node* previous_;
  Node* next_;
  TreeScope* tree_scope_;
  std::unique_ptr<NodeData> data_;
};

inline ContainerNode* Node::ParentOrShadowHostNode() const {
  return reinterpret_cast<ContainerNode*>(parent_or_shadow_host_node_);
}

inline void Node::SetParentOrShadowHostNode(ContainerNode* parent) {
  parent_or_shadow_host_node_ = reinterpret_cast<Node*>(parent);
}

}  // namespace kraken

#endif  // KRAKENBRIDGE_NODE_H