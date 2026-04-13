//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


public import PureLayout
import SignalServiceKit
import UIKit
extension UIView {

    // MARK: Superview edges

    @discardableResult
    func autoPinEdge(toSuperviewEdge edge: ALEdge, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: 0, relation: relation)
    }

    @discardableResult
    public func autoPinEdges(toSuperviewEdgesExcludingEdge edge: ALEdge) -> [NSLayoutConstraint] {
        return autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: edge)
    }

    // MARK: Superview safe area

    @discardableResult
    public func autoPinEdges(toSuperviewSafeAreaExcludingEdge edge: ALEdge) -> [NSLayoutConstraint] {
        return autoPinEdgesToSuperviewSafeArea(with: .zero, excludingEdge: edge)
    }

    // MARK: Horizontal edges to superview margins

    @discardableResult
    public func autoPinLeadingToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewMargin: .leading, withInset: inset)
    }

    @discardableResult
    public func autoPinTrailingToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewMargin: .trailing, withInset: inset)
    }

    @discardableResult
    public func autoPinWidthToSuperviewMargins(withInset inset: CGFloat) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(toSuperviewMargin: .leading, withInset: inset),
            autoPinEdge(toSuperviewMargin: .trailing, withInset: inset),
        ]
    }

    @discardableResult
    public func autoPinWidthToSuperviewMargins(relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of widths to the positioning of edges
        // "Width less than or equal to superview margin width"
        // -> "Leading edge greater than or equal to superview leading edge"
        // -> "Trailing edge less than or equal to superview trailing edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewMargin: .leading, relation: resolvedRelation),
            autoPinEdge(toSuperviewMargin: .trailing, relation: resolvedRelation),
        ]
    }

    // MARK: Vertical edges to superview margins

    @discardableResult
    public func autoPinTopToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewMargin: .top, withInset: inset)
    }

    @discardableResult
    public func autoPinBottomToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewMargin: .bottom, withInset: inset)
    }

    @discardableResult
    public func autoPinHeightToSuperviewMargins(relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of height to the positioning of edges
        // "Height less than or equal to superview margin height"
        // -> "Top edge greater than or equal to superview top edge"
        // -> "Bottom edge less than or equal to superview bottom edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewMargin: .top, relation: resolvedRelation),
            autoPinEdge(toSuperviewMargin: .bottom, relation: resolvedRelation),
        ]
    }

    // MARK: Width / height to superview

    @discardableResult
    public func autoPinWidthToSuperview(withMargin margin: CGFloat = 0, relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of widths to the positioning of edges
        // "Width less than or equal to superview margin width"
        // -> "Leading edge greater than or equal to superview leading edge"
        // -> "Trailing edge less than or equal to superview trailing edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewEdge: .leading, withInset: margin, relation: resolvedRelation),
            autoPinEdge(toSuperviewEdge: .trailing, withInset: margin, relation: resolvedRelation),
        ]
    }

    @discardableResult
    public func autoPinHeightToSuperview(withMargin margin: CGFloat = 0, relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of height to the positioning of edges
        // "Height less than or equal to superview margin height"
        // -> "Top edge greater than or equal to superview top edge"
        // -> "Bottom edge less than or equal to superview bottom edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewEdge: .top, withInset: margin, relation: resolvedRelation),
            autoPinEdge(toSuperviewEdge: .bottom, withInset: margin, relation: resolvedRelation),
        ]
    }

    // MARK: Edges to another view's edges

    @discardableResult
    public func autoPinEdges(toEdgesOf view: UIView, with insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(.leading, to: .leading, of: view, withOffset: insets.leading),
            autoPinEdge(.top, to: .top, of: view, withOffset: insets.top),
            autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -insets.trailing),
            autoPinEdge(.bottom, to: .bottom, of: view, withOffset: -insets.bottom),
        ]
    }

    @discardableResult
    public func autoPinLeading(toTrailingEdgeOf view: UIView, offset: CGFloat = 0) -> NSLayoutConstraint {
        autoPinEdge(.leading, to: .trailing, of: view, withOffset: offset)
    }

    @discardableResult
    public func autoPinTrailing(toLeadingEdgeOf view: UIView, offset: CGFloat = 0) -> NSLayoutConstraint {
        autoPinEdge(.trailing, to: .leading, of: view, withOffset: -offset)
    }

    @discardableResult
    public func autoPinHorizontalEdges(toEdgesOf view: UIView) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(.leading, to: .leading, of: view),
            autoPinEdge(.trailing, to: .trailing, of: view),
        ]
    }

    @discardableResult
    func autoPinVerticalEdges(toEdgesOf view: UIView) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(.top, to: .top, of: view),
            autoPinEdge(.bottom, to: .bottom, of: view),
        ]
    }

    @discardableResult
    func autoPinLeading(toEdgeOf view: UIView, offset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(.leading, to: .leading, of: view, withOffset: offset)
    }

    @discardableResult
    func autoPinTrailing(toEdgeOf view: UIView, offset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(.trailing, to: .trailing, of: view, withOffset: offset)
    }

    // MARK: Width & Height

    @discardableResult
    public func autoPinHeight(toHeightOf otherView: UIView, offset: CGFloat = 0, relation: NSLayoutConstraint.Relation = .equal) -> NSLayoutConstraint {
        return autoMatch(.height, to: .height, of: otherView, withOffset: offset, relation: relation)
    }

    @discardableResult
    public func autoPinWidth(toWidthOf otherView: UIView, offset: CGFloat = 0, relation: NSLayoutConstraint.Relation = .equal) -> NSLayoutConstraint {
        return autoMatch(.width, to: .width, of: otherView, withOffset: offset, relation: relation)
    }

    public static func matchWidthsOfViews(_ views: [UIView]) {
        var firstView: UIView?
        for view in views {
            if let otherView = firstView {
                view.autoMatch(.width, to: .width, of: otherView)
            } else {
                firstView = view
            }
        }
    }

    public static func matchHeightsOfViews(_ views: [UIView]) {
        var firstView: UIView?
        for view in views {
            if let otherView = firstView {
                view.autoMatch(.height, to: .height, of: otherView)
            } else {
                firstView = view
            }
        }
    }

    // MARK: Centering

    @discardableResult
    public func autoHCenterInSuperview() -> NSLayoutConstraint {
        return autoAlignAxis(.vertical, toSameAxisOf: superview!)
    }

    @discardableResult
    public func autoVCenterInSuperview() -> NSLayoutConstraint {
        return autoAlignAxis(.horizontal, toSameAxisOf: superview!)
    }

    // MARK: Aspect Ratio

    @discardableResult
    public func autoPinToSquareAspectRatio() -> NSLayoutConstraint {
        return autoPin(toAspectRatio: 1)
    }

    @discardableResult
    public func autoPinToAspectRatio(withSize size: CGSize) -> NSLayoutConstraint {
        return autoPin(toAspectRatio: size.aspectRatio)
    }

    @discardableResult
    public func autoPin(toAspectRatio ratio: CGFloat, relation: NSLayoutConstraint.Relation = .equal) -> NSLayoutConstraint {
        // Clamp to ensure view has reasonable aspect ratio.
        let clampedRatio: CGFloat = CGFloat.clamp(ratio, min: 0.05, max: 95.0)
        if clampedRatio != ratio {
            owsFailDebug("Invalid aspect ratio: \(ratio) for view: \(self)")
        }

        translatesAutoresizingMaskIntoConstraints = false
        let constraint = NSLayoutConstraint(
            item: self,
            attribute: .width,
            relatedBy: relation,
            toItem: self,
            attribute: .height,
            multiplier: clampedRatio,
            constant: 0,
        )
        constraint.autoInstall()
        return constraint
    }

    // MARK: Content Hugging and Compression Resistance

    public func setContentHuggingLow() {
        setContentHuggingHorizontalLow()
        setContentHuggingVerticalLow()
    }

    public func setContentHuggingHigh() {
        setContentHuggingHorizontalHigh()
        setContentHuggingVerticalHigh()
    }

    public func setContentHuggingHorizontalLow() {
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    public func setContentHuggingHorizontalHigh() {
        setContentHuggingPriority(.required, for: .horizontal)
    }

    public func setContentHuggingVerticalLow() {
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    public func setContentHuggingVerticalHigh() {
        setContentHuggingPriority(.required, for: .vertical)
    }

    public func setCompressionResistanceLow() {
        setCompressionResistanceHorizontalLow()
        setCompressionResistanceVerticalLow()
    }

    public func setCompressionResistanceHigh() {
        setCompressionResistanceHorizontalHigh()
        setCompressionResistanceVerticalHigh()
    }

    public func setCompressionResistanceHorizontalLow() {
        setContentCompressionResistancePriority(.init(0), for: .horizontal)
    }

    public func setCompressionResistanceHorizontalHigh() {
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    public func setCompressionResistanceVerticalLow() {
        setContentCompressionResistancePriority(.init(0), for: .vertical)
    }

    public func setCompressionResistanceVerticalHigh() {
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    func deactivateAllConstraints() {
        for constraint in constraints {
            constraint.isActive = false
        }
    }
}

extension NSLayoutConstraint.Relation {
    var inverse: NSLayoutConstraint.Relation {
        switch self {
        case .lessThanOrEqual: return .greaterThanOrEqual
        case .equal: return .equal
        case .greaterThanOrEqual: return .lessThanOrEqual
        @unknown default:
            owsFailDebug("Unknown case")
            return .equal
        }
    }
}
