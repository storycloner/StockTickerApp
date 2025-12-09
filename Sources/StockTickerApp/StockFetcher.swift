import Foundation

struct StockData {
    let symbol: String
    let price: Double
    let change: Double
    let percentChange: Double
}

protocol StockFetcher {
    func fetchStock(symbol: String) async throws -> StockData
}

// MARK: - Yahoo Finance Implementation

struct YahooRoot: Codable {
    let chart: YahooChart
}

struct YahooChart: Codable {
    let result: [YahooResult]?
    let error: YahooError?
}

struct YahooError: Codable {}

struct YahooResult: Codable {
    let meta: YahooMeta
    let timestamp: [Int]?
    let indicators: YahooIndicators?
}

struct YahooIndicators: Codable {
    let quote: [YahooQuote]
}

struct YahooQuote: Codable {
    let close: [Double?]
}

struct YahooMeta: Codable {
    let regularMarketPrice: Double
    let previousClose: Double?
    let chartPreviousClose: Double?
    let symbol: String
}

class YahooStockFetcher: StockFetcher {
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"]
        self.session = URLSession(configuration: config)
    }
    
    func fetchStock(symbol: String) async throws -> StockData {
        let querySymbol = mapSymbol(symbol)
        
        // Fetch 5 days to ensure we have history
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(querySymbol)?interval=1d&range=5d") else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let root = try JSONDecoder().decode(YahooRoot.self, from: data)
        guard let result = root.chart.result?.first else {
            throw URLError(.cannotParseResponse)
        }
        
        let meta = result.meta
        let price = meta.regularMarketPrice
        
        // 1. Try explicit previousClose from meta
        var prevClose = meta.previousClose
        
        // 2. If missing or invalid, try calculating from historical quotes
        if prevClose == nil || prevClose == 0.0 {
             if let closes = result.indicators?.quote.first?.close, closes.count >= 2 {
                 // The last item (index: count-1) is usually "Today/Current" (if market open) or "Last Session" (if market closed)
                 // BUT 'regularMarketPrice' is the live price.
                 // So we generally want the close of the *day before the current active session*.
                 
                 // If the last timestamp is today, we want the one before it.
                 // If the last timestamp was yesterday (market closed), we want the one before THAT?
                 // No, standard change is `Current - PreviousSessionClose`.
                 
                 // Let's assume the array is ordered. 
                 // We grab the last valid 'close' that is NOT the current real-time price.
                 // Actually, simpler heuristic:
                 // The API usually returns `chartPreviousClose` correctly for the *start* of the period or something.
                 // Let's look at the penultimate close.
                 
                 // Filter out nils
                 let validCloses = closes.compactMap { $0 }
                 if validCloses.count >= 2 {
                     // If the market is active, the last close in array is essentially the current price.
                     // So we want the one before it.
                     prevClose = validCloses[validCloses.count - 2]
                 } else if let first = validCloses.first {
                     prevClose = first
                 }
             }
        }
        
        // 3. Fallback to chartPreviousClose
        if prevClose == nil || prevClose == 0.0 {
            prevClose = meta.chartPreviousClose
        }
        
        // 4. Absolute fallback
        let finalPrevClose = prevClose ?? price
        
        let change = price - finalPrevClose
        let percent = finalPrevClose != 0 ? (change / finalPrevClose) * 100 : 0.0
        
        return StockData(
            symbol: symbol,
            price: price,
            change: change,
            percentChange: percent
        )
    }
    
    private func mapSymbol(_ symbol: String) -> String {
        switch symbol.uppercased() {
        case "SPX", "S&P500": return "%5EGSPC"
        case "IXIC", "NAS", "NASDAQ": return "%5EIXIC"
        case "DJI", "DOW": return "%5EDJI"
        default: return symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        }
    }
}

// Keep Mock for fallback or testing if needed, but unused now
class MockStockFetcher: StockFetcher {
    func fetchStock(symbol: String) async throws -> StockData {
        try await Task.sleep(nanoseconds: 200 * 1_000_000)
        let basePrice = Double.random(in: 100...5000)
        let change = Double.random(in: -50...50)
        return StockData(symbol: symbol, price: basePrice, change: change, percentChange: 0.0)
    }
}
