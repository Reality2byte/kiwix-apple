// This file is part of Kiwix for iOS & macOS.
//
// Kiwix is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// any later version.
//
// Kiwix is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Kiwix; If not, see https://www.gnu.org/licenses/.

import SwiftUI

enum CellBackground {
    #if os(macOS)
    private static let normal: Color = Color(nsColor: NSColor.controlBackgroundColor)
    private static let selected: Color = Color(nsColor: NSColor.selectedControlColor)
    #else
    private static let normal: Color = .secondaryBackground
    private static let selected: Color = .tertiaryBackground
    #endif
    
    static func colorFor(isHovering: Bool, isSelected: Bool = false) -> Color {
        #if os(macOS)
        if isSelected {
            isHovering ? selected.opacity(0.75) : selected
        } else {
            isHovering ? selected.opacity(0.5) : normal
        }
        #else
        isHovering ? selected : normal
        #endif
    }
    
    static let clipShapeRectangle = RoundedRectangle(cornerRadius: 12, style: .continuous)
    
    static func hotspotSelectionColorFor(isHovering: Bool, isSelected: Bool) -> Color {
        #if os(macOS)
        colorFor(isHovering: isHovering, isSelected: isSelected)
        #else
        isSelected ? .accentColor.opacity(0.5) : normal
        #endif
    }
}
