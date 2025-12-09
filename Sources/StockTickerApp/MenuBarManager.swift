import Cocoa

@MainActor
class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var fetcher: StockFetcher = YahooStockFetcher()
    
    // Default tickers - loaded from UserDefaults if available
    private var tickers: [String] {
        didSet {
            saveTickers()
            currentTickerIndex = 0
            rebuildMenu()
        }
    }
    private var currentTickerIndex = 0
    private var isMarqueeMode = false
    // Cache the full colored string to avoid rebuilding it every frame
    private var marqueeDetails: (text: NSAttributedString, offset: Int) = (NSAttributedString(), 0)
    private var marqueeTimer: Timer?
    
    // Data cache
    private var stockData: [String: StockData] = [:]
    
    override init() {
        // Load tickers or default
        if let saved = UserDefaults.standard.stringArray(forKey: "savedTickers") {
            self.tickers = saved
        } else {
            self.tickers = ["SPX", "IXIC", "DJI", "AAPL"]
        }
        super.init()
    }
    
    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "Loading..."
        }
        
        // Load settings
        isMarqueeMode = UserDefaults.standard.bool(forKey: "isMarqueeMode")
        
        setupMenu() // Initial setup
        startFetching()
        startTimers()
    }
    
    private func saveTickers() {
        UserDefaults.standard.set(tickers, forKey: "savedTickers")
    }
    
    private func setupMenu() {
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        let menu = NSMenu()
        
        // 1. Controls
        let marqueeItem = NSMenuItem(title: "Marquee Mode", action: #selector(toggleMarqueeMode), keyEquivalent: "m", target: self)
        marqueeItem.state = isMarqueeMode ? .on : .off
        menu.addItem(marqueeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Manage Tickers (Bulk)...", action: #selector(manageTickersClicked), keyEquivalent: "b", target: self))
        menu.addItem(NSMenuItem(title: "Remove Current Ticker", action: #selector(removeCurrentTickerClicked), keyEquivalent: "d", target: self))
        menu.addItem(NSMenuItem(title: "Reset Tickers", action: #selector(resetTickersClicked), keyEquivalent: "", target: self))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r", target: self))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit (v1.3)", action: #selector(quitClicked), keyEquivalent: "q", target: self))
        
        statusItem.menu = menu
    }
    
    private func startFetching() {
        // Initial fetch
        Task { await fetchAll() }
        
        // Periodic fetch every 60 seconds
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.fetchAll() }
        }
    }
    
    private func startTimers() {
        // Invalidate existing timer
        timer?.invalidate()
        marqueeTimer?.invalidate()
        
        if isMarqueeMode {
            // Marquee: Update frequently to scroll text
            // Tune for smoothness/speed: 0.15s ~ 6.6 chars/second
            marqueeDetails = (buildMarqueeString(), 0)
            marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.updateMarqueeDisplay()
            }
        } else {
             // Rotation: Update every 5 seconds
             timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                 self?.rotateDisplay()
             }
             // Update immediately to ensure correct mode shown
             updateDisplay()
        }
    }
    
    // Unused in new logic but kept for clean diff if needed
    private func startRotating() {
         startTimers()
    }
    
    private func rotateDisplay() {
        currentTickerIndex += 1
        updateDisplay()
        // Rebuild menu to update checkmark
        setupMenu() // efficient enough for 5s interval
    }
    
    private func buildMarqueeString() -> NSAttributedString {
        let fullString = NSMutableAttributedString()
        let separator = NSAttributedString(string: "   |   ", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        
        for (index, ticker) in tickers.enumerated() {
            if let data = stockData[ticker] {
                let arrow = data.change >= 0 ? "▲" : "▼"
                let priceStr = data.price.formatted(.number.precision(.fractionLength(2)))
                let changeStr = abs(data.change).formatted(.number.precision(.fractionLength(2)))
                let text = "\(ticker) \(priceStr) \(arrow)\(changeStr)"
                
                let color = data.change >= 0 ? NSColor.systemGreen : NSColor.systemRed
                // Use monospaced font for stability
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: color,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
                ]
                
                fullString.append(NSAttributedString(string: text, attributes: attrs))
            } else {
                fullString.append(NSAttributedString(string: ticker))
            }
            
            // Add separator (except maybe at very end? but we loop so it is fine)
            fullString.append(separator)
        }
        return fullString
    }
    
    private func updateMarqueeDisplay() {
        guard let button = statusItem.button else { return }
        
        let fullAttributed = marqueeDetails.text
        let length = fullAttributed.length
        guard length > 0 else { return }
        
        // Window length (chars) - might need to adjust based on width? 
        // 30 chars is a good guess.
        let windowLen = 40 
        
        var start = marqueeDetails.offset
        
        // Loop logic: We need to virtually concatenate string to itself
        // A simple way is to build a temporary string of (Full + Full) then substring
        // But for Attributed String that might be heavy to do every 0.05s.
        // Actually, appending two attributed strings is cheap enough.
        
        if start >= length {
            start = 0 // loop back
        }
        
        let combined = NSMutableAttributedString(attributedString: fullAttributed)
        combined.append(fullAttributed) // Double it to handle wrap around
        
        // Ensure we don't go out of bounds even on the doubled string
        let effectiveLen = windowLen
        
        if start + effectiveLen <= combined.length {
            let visible = combined.attributedSubstring(from: NSRange(location: start, length: effectiveLen))
            button.attributedTitle = visible
        }
        
        marqueeDetails.offset = start + 1
    }
    
    private func fetchAll() async {
        // Create a local copy to iterate safely
        let currentTickers = tickers
        
        for ticker in currentTickers {
            do {
                let data = try await fetcher.fetchStock(symbol: ticker)
                stockData[ticker] = data
            } catch {
                print("Error fetching \(ticker): \(error)")
            }
        }
        // Force Update display
        if isMarqueeMode {
            marqueeDetails.text = buildMarqueeString()
        } else {
            self.updateDisplay()
        }
    }
    
    @objc private func updateDisplay() {
        guard !tickers.isEmpty else { 
            statusItem.button?.title = "No Tickers"
            return 
        }
        
        let index = currentTickerIndex % tickers.count
        let symbol = tickers[index]
        
        guard let data = stockData[symbol], let button = statusItem.button else { 
            // If data is missing but we have tickers, maybe show "Loading [Symbol]"
            if let button = statusItem.button {
                button.title = "\(symbol)..."
            }
            return 
        }
        
        let arrow = data.change >= 0 ? "▲" : "▼"
        let formattedChange = String(format: "%.2f", abs(data.change))
        let displayString = "\(symbol) \(data.price.formatted(.number.precision(.fractionLength(2)))) \(arrow)\(formattedChange)"
        
        button.title = displayString
        
        if data.change >= 0 {
             button.attributedTitle = NSAttributedString(string: displayString, attributes: [.foregroundColor: NSColor.systemGreen])
        } else {
             // For red, systemRed is good.
             button.attributedTitle = NSAttributedString(string: displayString, attributes: [.foregroundColor: NSColor.systemRed])
        }
    }
    
    @objc func addTickerClicked() {
        if tickers.count >= 10 {
            let limitAlert = NSAlert()
            limitAlert.messageText = "Limit Reached"
            limitAlert.informativeText = "You can only have up to 10 tickers."
            limitAlert.runModal()
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Add Stock Ticker"
        alert.informativeText = "Enter the symbol (e.g., TSLA):"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = inputField
        
        // Focus the input field
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let symbol = inputField.stringValue.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !symbol.isEmpty && !tickers.contains(symbol) {
                tickers.append(symbol)
                
                // Jump to the new ticker immediately
                if let newIndex = tickers.firstIndex(of: symbol) {
                    currentTickerIndex = newIndex
                    // Pause rotation briefly so they can see it? 
                    // For now just update display
                    updateDisplay() 
                    // Restart fetch for this specific one if needed, but fetchAll handles it
                    Task { 
                        // Fetch just this one for speed
                        do {
                           let data = try await fetcher.fetchStock(symbol: symbol)
                           stockData[symbol] = data
                           updateDisplay()
                        } catch {
                            print("Error processing new ticker \(symbol)")
                        }
                    }
                }
            }
        }
    }
    
    @objc func removeCurrentTickerClicked() {
        guard !tickers.isEmpty else { return }
        
        let indexToRemove = currentTickerIndex % tickers.count
        let symbolToRemove = tickers[indexToRemove]
        
        tickers.remove(at: indexToRemove)
        stockData.removeValue(forKey: symbolToRemove)
        
        // Adjust index if needed
        if currentTickerIndex >= tickers.count {
            currentTickerIndex = 0
        }
        
        // Update menu immediately so indices stay valid
        setupMenu()
        updateDisplay()
    }
    
    @objc func manageTickersClicked() {
        let alert = NSAlert()
        alert.messageText = "Manage Tickers"
        alert.informativeText = "Edit your tickers below (one per line or comma separated). Existing tickers will be replaced."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.minSize = NSSize(width: 0.0, height: 200)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = tickers.joined(separator: "\n")
        
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = textView.string
            // Parse: split by newlines or commas
            let newTickers = text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
            
            // Remove duplicates while preserving order
            var unique: [String] = []
            for t in newTickers {
                if !unique.contains(t) { unique.append(t) }
            }
            
            // Limit to 10
            if unique.count > 10 {
                unique = Array(unique.prefix(10))
                // Optional: warn user? For now just truncate as requested "limit to 10"
            }
            
            if !unique.isEmpty {
                self.tickers = unique
                Task { await fetchAll() }
            }
        }
    }
    
    @objc func resetTickersClicked() {
        tickers = ["SPX", "IXIC", "DJI", "AAPL"]
        Task { await fetchAll() }
    }
    
    @objc func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func refreshClicked() {
        Task { await fetchAll() }
    }
    
    @objc func toggleMarqueeMode() {
        isMarqueeMode.toggle()
        UserDefaults.standard.set(isMarqueeMode, forKey: "isMarqueeMode")
        
        // Restart timers to switch modes
        startTimers()
        
        // Rebuild menu to show checkbox state
        setupMenu()
    }
    
    @objc func tickerItemClicked(_ sender: NSMenuItem) {
        if !isMarqueeMode {
            currentTickerIndex = sender.tag
            updateDisplay()
            setupMenu() // update checkmark
        }
    }
}

// Extension to help key target action
private extension NSMenuItem {
    convenience init(title: String, action: Selector, keyEquivalent: String, target: AnyObject?) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
