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
        // Yahoo requires a User-Agent to avoid blocking
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"]
        self.session = URLSession(configuration: config)
    }
    
    func fetchStock(symbol: String) async throws -> StockData {
        // Handle indices that need special encoding if necessary?
        // Yahoo uses ^GSPC for SP500, ^IXIC for Nasdaq, ^DJI for Dow
        // But users might type SPX, IXIC, DJI. We should map them.
        let querySymbol = mapSymbol(symbol)
        
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
        let prevClose = meta.previousClose ?? meta.chartPreviousClose ?? price
        let change = price - prevClose
        
        let percent = (change / prevClose) * 100
        
        return StockData(
            symbol: symbol, // Return the requested symbol name (e.g. SPX) not the yahoo one (^GSPC)
            price: price,
            change: change,
            percentChange: percent
        )
    }
    
    private func mapSymbol(_ symbol: String) -> String {
        switch symbol.uppercased() {
        case "SPX", "S&P500": return "%5EGSPC" // URL encoded ^GSPC
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
