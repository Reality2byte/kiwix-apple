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

#if os(macOS)
import SwiftUI

struct DownloadsMacOsLocationPicker: View {
    @State private var location = DownloadLocationMac.load()
    @State private var volumeAndSpace: String?
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(location.urlDescription)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let volumeAndSpace {
                    Label(volumeAndSpace, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    Button(LocalString.download_mac_folder_button_change) {
                        changeDirectory()
                    }
                    if !location.isDefault {
                        Button(LocalString.download_mac_folder_button_reset) {
                            resetToDefault()
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .onAppear {
            location = DownloadLocationMac.load()
            refreshVolumeAndSpace()
        }
    }
    
    // MARK: - Actions
    
    private func changeDirectory() {
        let panel = NSOpenPanel()
        panel.message = LocalString.download_mac_folder_panel_message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        // Start in the current directory if available
        if let currentDir = location.directory {
            panel.directoryURL = currentDir
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                setUserDefinedDir(url)
            }
        }
    }
    
    private func setUserDefinedDir(_ url: URL) {
        guard FileManager.default.isWritableFile(atPath: url.path()) else {
            return showAlert(message: LocalString.download_mac_folder_error_title,
                             description: LocalString.download_mac_folder_error_not_writable)
        }
        location = DownloadLocationMac(directory: url)
        saveLocation()
    }
    
    private func resetToDefault() {
        location = DownloadLocationMac.default()
        saveLocation()
    }
    
    private func saveLocation() {
        if !location.save() {
            showAlert(message: LocalString.download_mac_folder_error_title,
                      description: LocalString.download_mac_folder_error_save_failed)
        }
        refreshVolumeAndSpace()
    }
    
    private func refreshVolumeAndSpace() {
        Task.detached(priority: .utility) {
            let value = await location.volumeAndSpace()
            await MainActor.run { volumeAndSpace = value }
        }
    }
    
    private func showAlert(message: String, description: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = description
        alert.alertStyle = .warning
        alert.addButton(withTitle: LocalString.common_button_ok)
        alert.runModal()
        return
    }
}

#endif
