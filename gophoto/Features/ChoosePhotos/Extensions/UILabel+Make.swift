//
//  UILabel+Make.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

extension UILabel {
    static func make(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .preferredFont(forTextStyle: style)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = Theme.text
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }
}
