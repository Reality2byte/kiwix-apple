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

struct KeyPressHandler: ViewModifier {
    
    let key: KeyEquivalent
    let action: () -> Void
    
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            newApi(content: content)
        } else {
            content
        }
        #else
        content
        #endif
    }
    
    @available(macOS 14.0, iOS 17.0, *)
    private func newApi(content: Content) -> some View {
        content.onKeyPress(key, action: {
            Task { await MainActor.run {
                action()
            }}
            return .handled
        })
    }
}
