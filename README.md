# Stock Ticker Menu Bar App

A lightweight, native macOS menu bar application that displays real-time stock prices and indices.

## Features

*   **Real-time Data**: Fetches live stock data using Yahoo Finance API.
*   **Menu Bar Widget**: prices scroll or rotate directly in your menu bar.
*   **Modes**:
    *   **Rotating**: Cycles through your stocks one by one.
    *   **Marquee**: Continuous scrolling ticker tape (Classic visual).
*   **Customizable**:
    *   Manage tickers (Bulk add/remove).
    *   Color-coded price changes (Green/Red).
    *   Visual indicators (▲/▼).
*   **Native Performance**: Built with Swift and Cocoa for minimal footprint.

## Installation

### From Source
1.  Clone the repository.
2.  Run the build script:
    ```bash
    ./package_app.sh
    ```
3.  The app will be created in `dist/StockTicker.app`.
4.  Drag it to your Applications folder.

## Usage

*   **Click** the ticker in the menu bar to open settings.
*   **Manage Tickers**: Add your favorite stocks (e.g., AAPL, TSLA, BTC-USD). Max 10 tickers.
*   **Marquee Mode**: Toggle for a scrolling effect.

## Development

Built with Swift 5.7+ and AppKit.

### Project Structure
*   `Sources/StockTickerApp`: Core application logic.
    *   `AppEntry.swift`: Entry point (`@main`).
    *   `MenuBarManager.swift`: UI and logic controller.
    *   `StockFetcher.swift`: Networking and data model.
*   `package_app.sh`: Script to compile and bundle the `.app`.

### Building
```bash
swift build -c release
```

## License
MIT
