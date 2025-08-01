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
import UniformTypeIdentifiers

/// Button that presents a file importer.
/// Note 1: Does not work on iOS / iPadOS via commands.
/// Note 2: Does not allow multiple selection,
///     because we want a new tab to be opened with main page when file is opened,
///     and the multitab implementation on iOS / iPadOS does not support open multiple tabs with an url right now.
struct OpenFileButton<Label: View>: View {
    @State private var isPresented: Bool = false

    let context: OpenFileContext
    let label: Label

    init(context: OpenFileContext, @ViewBuilder label: () -> Label) {
        self.context = context
        self.label = label()
    }

    var body: some View {
        Button {
            isPresented = true
        } label: { label }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [UTType.zimFile],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result else { return }
            NotificationCenter.openFiles(urls, context: context)
        }
        .help(LocalString.common_dialog_button_open)
        .keyboardShortcut("o")
    }
}

enum OpenFileAlert {
    case unableToOpen(filenames: [String])
}

struct OpenFileHandler: ViewModifier {
    @EnvironmentObject private var navigation: NavigationViewModel
    @State private var isAlertPresented = false
    @State private var activeAlert: OpenFileAlert?

    private let openFiles = NotificationCenter.default.publisher(for: .openFiles)

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func body(content: Content) -> some View {
        content.onReceive(openFiles) { notification in
            guard let urls = notification.userInfo?["urls"] as? [URL],
                  let context = notification.userInfo?["context"] as? OpenFileContext else { return }

            Task { @MainActor in
                // try open zim files
                var openedZimFileIDs = Set<UUID>()
                var invalidURLs = Set<URL>()
                for url in urls {
                    if let metadata = await LibraryOperations.open(url: url) {
                        openedZimFileIDs.insert(metadata.fileID)
                    } else {
                        invalidURLs.insert(url)
                    }
                }
                
                // action for zim files that can be opened (e.g. open main page)
                if case .library = context {
                    // don't need to open the main page
                    // but we should select it to show the details
                    // if there's only one ZIM file imported
                    if openedZimFileIDs.count == 1, let firstFileID = openedZimFileIDs.first {
                        NotificationCenter.selectFileBy(fileId: firstFileID)
                    }
                } else {
                    for fileID in openedZimFileIDs {
                        if let url = await ZimFileService.shared.getMainPageURL(zimFileID: fileID) {
                            // action for zim files that can be opened (e.g. open main page)
                            switch context {
                            #if os(iOS)
                            case .file(.none):
                                NotificationCenter.openURL(url, inNewTab: true)
                            case .file(.some(let deepLinkID)):
                                NotificationCenter.openURL(
                                    url,
                                    inNewTab: true,
                                    context: .deepLink(id: deepLinkID)
                                )
                            #else
                            case .command:
                                NotificationCenter.openURL(url, inNewTab: true)
                            #endif
                            case .welcomeScreen:
                                NotificationCenter.openURL(url)
                            case .library:
                                break
                            }
                        }
                    }
                }
                // show alert if there are any files that cannot be opened
                if !invalidURLs.isEmpty {
                    isAlertPresented = true
                    activeAlert = .unableToOpen(filenames: invalidURLs.map({ $0.lastPathComponent }))
                }
            }
        }.alert(LocalString.file_import_alert_no_open_title,
                isPresented: $isAlertPresented, presenting: activeAlert) { _ in
        } message: { alert in
            switch alert {
            case .unableToOpen(let filenames):
                let name = ListFormatter.localizedString(byJoining: filenames)
                Text(LocalString.file_import_alert_no_open_message(withArgs: name))
            }
        }
    }
}
