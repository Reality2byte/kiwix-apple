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

import Combine
import CoreData
import SwiftUI
import WebKit
import Defaults

#if os(macOS)
struct WebView: NSViewRepresentable {
    @ObservedObject var browser: BrowserViewModel
    
    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        let webView = browser.webView
        enableAutoLayout(nsView: nsView, webView: webView)
        return nsView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(view: self,
                    onChangingFullscreen: { (enters: Bool, webView: WKWebView) in
            guard let nsView = webView.superview else { return }
            if enters {
                // auto-layout is not working
                // when the video is paused in full screen
                disableAutoLayout(nsView: nsView, webView: webView)
            } else {
                enableAutoLayout(nsView: nsView, webView: webView)
            }
        })
    }
    
    @MainActor
    private func enableAutoLayout(nsView: NSView, webView: WKWebView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        nsView.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: nsView.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: nsView.safeAreaLayoutGuide.trailingAnchor),
            webView.topAnchor.constraint(equalTo: nsView.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: nsView.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    @MainActor
    private func disableAutoLayout(nsView: NSView, webView: WKWebView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        nsView.addSubview(webView)
    }

    final class Coordinator {
        private let pageZoomObserver: Defaults.Observation
        private let fullScreenObserver: NSKeyValueObservation

        @MainActor
        init(
            view: WebView,
            onChangingFullscreen: @escaping @Sendable @MainActor (_ enters: Bool, _ webView: WKWebView) -> Void
        ) {
            let browser = view.browser
            pageZoomObserver = Defaults.observe(.webViewPageZoom) { [weak browser] change in
                browser?.webView.pageZoom = change.newValue
            }
            fullScreenObserver = view.browser.webView.observe(\.fullscreenState, options: [.new]) { webView, _ in
                Task { @MainActor in
                    switch webView.fullscreenState {
                    case .enteringFullscreen:
                        onChangingFullscreen(true, webView)
                    case .inFullscreen:
                        break
                    case .exitingFullscreen:
                        onChangingFullscreen(false, webView)
                    case .notInFullscreen:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
        
        deinit {
            pageZoomObserver.invalidate()
            fullScreenObserver.invalidate()
        }
    }
}

#elseif os(iOS)
struct WebView: UIViewControllerRepresentable {
    @ObservedObject var browser: BrowserViewModel

    func makeUIViewController(context: Context) -> WebViewController {
        WebViewController(webView: browser.webView)
    }

    func updateUIViewController(_ controller: WebViewController, context: Context) { }
}

final class WebViewController: UIViewController {
    private let webView: WKWebView
    private let pageZoomObserver: Defaults.Observation
    private var topSafeAreaConstraint: NSLayoutConstraint?
    private var layoutSubject = PassthroughSubject<Void, Never>()
    private var layoutCancellable: AnyCancellable?
    
    init(webView: WKWebView) {
        self.webView = webView
        pageZoomObserver = Defaults.observe(.webViewPageZoom) { change in
            webView.adjustTextSize(pageZoom: change.newValue)
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        webView.scrollView.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        webView.alpha = 0

        /*
         HACK: Make sure the webview content does not jump after state restoration
         It appears the webview's state restoration does not properly take into account of the content inset.
         To mitigate, first pin the webview's top against safe area top anchor, after all viewDidLayoutSubviews calls,
         pin the webview's top against view's top anchor, so that content does not appears to move up.
         */
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: webView.leftAnchor),
            view.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            view.rightAnchor.constraint(equalTo: webView.rightAnchor)
        ])
        topSafeAreaConstraint = view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: webView.topAnchor)
        topSafeAreaConstraint?.isActive = true
        layoutCancellable = layoutSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let view = self?.view,
                      let webView = self?.webView,
                      view.subviews.contains(webView) else { return }
                webView.alpha = 1
                guard self?.topSafeAreaConstraint?.isActive == true else { return }
                self?.topSafeAreaConstraint?.isActive = false
                self?.view.topAnchor.constraint(equalTo: webView.topAnchor).isActive = true
            }
        if !Brand.disableImmersiveReading {
            parent?.navigationController?.hidesBarsOnSwipe = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if #unavailable(iOS 18.0) {
            webView.setValue(view.safeAreaInsets, forKey: "_obscuredInsets")
        }
        layoutSubject.send()
    }
}

extension WKWebView {
    func adjustTextSize(pageZoom: Double? = nil) {
        let pageZoom = pageZoom ?? Defaults[.webViewPageZoom]
        let template = "document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust='%.0f%%'"
        let javascript = String(format: template, pageZoom * 100)
        evaluateJavaScript(javascript, completionHandler: nil)
    }
}
#endif
