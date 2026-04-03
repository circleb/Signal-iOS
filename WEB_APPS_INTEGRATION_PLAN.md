# Web Apps Integration Implementation Guide for Signal App

## Overview

Integrate web apps from the Homestead Heritage API into the Signal app's existing tab view. Users will see a new "Web Apps" button in the tab bar that opens a popup list of available web applications. Each web app entry will open in a webview that loads the hosted application. The feature will fetch web app data from `homesteadheeritage.org/api/v2/webapps.php` and display them in a categorized, searchable interface.

## API Configuration

- **API Endpoint**: `https://homesteadheeritage.org/api/v2/webapps.php`
- **Data Format**: JSON array of web app objects
- **Authentication**: None required (public API)
- **Caching**: Implement local caching for offline access

## Data Structure

```swift
struct WebApp: Codable {
    let entry: String           // Domain/URL for the web app
    let name: String           // Display name
    let description: String    // App description
    let icon: String          // SF Symbol name
    let image: String         // Background image filename
    let category: String      // Category for grouping
    let urlsPermitted: [String] // Allowed URL patterns
    let location: [String]    // Where to show the app
    let type: String          // App type (sublist, rss, etc.)
    let parent: String        // Parent app reference
}

struct WebAppCategory: Codable {
    let name: String
    let apps: [WebApp]
    let icon: String
}
```

## Implementation Steps

### Step 1: Create Web Apps Infrastructure

#### 1.1 Create Web Apps Configuration

**File**: `SignalServiceKit/Account/WebAppsConfig.swift`

```swift
struct WebAppsConfig {
    static let apiEndpoint = "https://homesteadheeritage.org/api/v2/webapps.php"
    static let cacheKey = "web_apps_cache"
    static let cacheExpirationInterval: TimeInterval = 3600 // 1 hour

    // Web app categories
    static let defaultCategories = [
        "Community Updates",
        "Communication",
        "Resources",
        "Tools"
    ]

    // Default icons for categories
    static let categoryIcons = [
        "Community Updates": "newspaper.fill",
        "Communication": "message.fill",
        "Resources": "folder.fill",
        "Tools": "wrench.and.screwdriver.fill"
    ]
}
```

#### 1.2 Create Web Apps Service

**File**: `SignalServiceKit/Account/WebAppsService.swift`

```swift
protocol WebAppsServiceProtocol {
    func fetchWebApps() -> Promise<[WebApp]>
    func getCachedWebApps() -> [WebApp]?
    func cacheWebApps(_ apps: [WebApp])
    func clearCache()
    func getWebAppsByCategory() -> [WebAppCategory]
    func searchWebApps(query: String) -> [WebApp]
    func getWebAppsByLocation(_ location: String) -> [WebApp]
}

class WebAppsService: WebAppsServiceProtocol {
    private let networkManager: NetworkManager
    private let cache: KeyValueStore

    init(networkManager: NetworkManager, cache: KeyValueStore) {
        self.networkManager = networkManager
        self.cache = cache
    }

    func fetchWebApps() -> Promise<[WebApp]> {
        return Promise { seal in
            let request = TSRequest(url: URL(string: WebAppsConfig.apiEndpoint)!)

            networkManager.makeRequest(request)
                .done { response in
                    if let data = response.responseData,
                       let webApps = try? JSONDecoder().decode([WebApp].self, from: data) {
                        self.cacheWebApps(webApps)
                        seal.fulfill(webApps)
                    } else {
                        seal.reject(WebAppsError.invalidResponse)
                    }
                }
                .catch { error in
                    seal.reject(WebAppsError.networkError(error))
                }
        }
    }

    func getWebAppsByCategory() -> [WebAppCategory] {
        let apps = getCachedWebApps() ?? []
        let grouped = Dictionary(grouping: apps) { $0.category }

        return grouped.map { category, apps in
            WebAppCategory(
                name: category,
                apps: apps.sorted { $0.name < $1.name },
                icon: WebAppsConfig.categoryIcons[category] ?? "app.fill"
            )
        }.sorted { $0.name < $1.name }
    }

    func searchWebApps(query: String) -> [WebApp] {
        let apps = getCachedWebApps() ?? []
        let lowercasedQuery = query.lowercased()

        return apps.filter { app in
            app.name.lowercased().contains(lowercasedQuery) ||
            app.description.lowercased().contains(lowercasedQuery) ||
            app.category.lowercased().contains(lowercasedQuery)
        }
    }
}
```

#### 1.3 Create Web Apps Store

**File**: `SignalServiceKit/Account/WebAppsStore.swift`

```swift
protocol WebAppsStore {
    func storeWebApps(_ apps: [WebApp])
    func getWebApps() -> [WebApp]?
    func clearWebApps()
    func getLastFetchDate() -> Date?
    func isCacheExpired() -> Bool
    func getWebApp(by entry: String) -> WebApp?
    func getWebAppsByType(_ type: String) -> [WebApp]
}

class WebAppsStoreImpl: WebAppsStore {
    private let keyValueStore: KeyValueStore

    init(keyValueStore: KeyValueStore) {
        self.keyValueStore = keyValueStore
    }

    func storeWebApps(_ apps: [WebApp]) {
        if let data = try? JSONEncoder().encode(apps) {
            keyValueStore.setData(data, key: WebAppsConfig.cacheKey)
            keyValueStore.setDate(Date(), key: "\(WebAppsConfig.cacheKey)_last_fetch")
        }
    }

    func getWebApps() -> [WebApp]? {
        guard let data = keyValueStore.getData(WebAppsConfig.cacheKey),
              let apps = try? JSONDecoder().decode([WebApp].self, from: data) else {
            return nil
        }
        return apps
    }

    func isCacheExpired() -> Bool {
        guard let lastFetch = getLastFetchDate() else { return true }
        return Date().timeIntervalSince(lastFetch) > WebAppsConfig.cacheExpirationInterval
    }
}
```

### Step 2: Create Web Apps UI Components

#### 2.1 Create Web Apps Tab Bar Item

**File**: `Signal/ConversationView/WebAppsTabBarItem.swift`

```swift
class WebAppsTabBarItem: UITabBarItem {
    init() {
        super.init()
        title = "Web Apps"
        image = UIImage(systemName: "globe")
        selectedImage = UIImage(systemName: "globe.fill")
        tag = 4 // Adjust based on existing tab indices
    }
}
```

#### 2.2 Create Web Apps List View Controller

**File**: `Signal/ConversationView/WebAppsListViewController.swift`

```swift
class WebAppsListViewController: UIViewController {
    private let webAppsService: WebAppsServiceProtocol
    private let searchController = UISearchController(searchResultsController: nil)

    // UI Components
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let emptyStateView = EmptyStateView()

    // Data
    private var categories: [WebAppCategory] = []
    private var filteredCategories: [WebAppCategory] = []
    private var isSearching = false

    init(webAppsService: WebAppsServiceProtocol) {
        self.webAppsService = webAppsService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSearchController()
        loadWebApps()
    }

    private func setupUI() {
        title = "Web Apps"
        view.backgroundColor = Theme.backgroundColor

        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(WebAppCell.self, forCellReuseIdentifier: "WebAppCell")
        tableView.register(WebAppCategoryHeaderView.self, forHeaderFooterViewReuseIdentifier: "CategoryHeader")

        // Setup refresh control
        refreshControl.addTarget(self, action: #selector(refreshWebApps), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // Layout
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search web apps..."
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    @objc private func refreshWebApps() {
        loadWebApps(showLoading: false)
    }

    private func loadWebApps(showLoading: Bool = true) {
        if showLoading {
            loadingIndicator.startAnimating()
        }

        webAppsService.fetchWebApps()
            .done { [weak self] apps in
                self?.categories = self?.webAppsService.getWebAppsByCategory() ?? []
                self?.updateUI()
            }
            .catch { [weak self] error in
                self?.showError(error)
            }
            .finally { [weak self] in
                self?.loadingIndicator.stopAnimating()
                self?.refreshControl.endRefreshing()
            }
    }

    private func updateUI() {
        if isSearching {
            // Show filtered results
            tableView.reloadData()
        } else {
            // Show all categories
            filteredCategories = categories
            tableView.reloadData()
        }

        emptyStateView.isHidden = !filteredCategories.isEmpty
    }
}
```

#### 2.3 Create Web App Cell

**File**: `Signal/ConversationView/WebAppCell.swift`

```swift
class WebAppCell: UITableViewCell {
    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let categoryLabel = UILabel()
    private let backgroundImageView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        // Background image
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.layer.cornerRadius = 12
        backgroundImageView.alpha = 0.1

        // Icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = Theme.primaryColor

        // Labels
        nameLabel.font = .ows_dynamicTypeTitle2
        nameLabel.textColor = Theme.primaryTextColor

        descriptionLabel.font = .ows_dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextColor
        descriptionLabel.numberOfLines = 2

        categoryLabel.font = .ows_dynamicTypeCaption1
        categoryLabel.textColor = Theme.accentColor

        // Layout
        contentView.addSubview(backgroundImageView)
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(categoryLabel)

        backgroundImageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))

        iconImageView.autoSetDimensions(to: CGSize(width: 40, height: 40))
        iconImageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 24)
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)

        nameLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 12)
        nameLabel.autoPinEdge(.top, to: .top, of: iconImageView)
        nameLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        descriptionLabel.autoPinEdge(.leading, to: .leading, of: nameLabel)
        descriptionLabel.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: 4)
        descriptionLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        categoryLabel.autoPinEdge(.leading, to: .leading, of: descriptionLabel)
        categoryLabel.autoPinEdge(.top, to: .bottom, of: descriptionLabel, withOffset: 8)
        categoryLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)
    }

    func configure(with webApp: WebApp) {
        nameLabel.text = webApp.name
        descriptionLabel.text = webApp.description
        categoryLabel.text = webApp.category

        // Set icon
        if let icon = UIImage(systemName: webApp.icon) {
            iconImageView.image = icon
        } else {
            iconImageView.image = UIImage(systemName: "app.fill")
        }

        // Set background image if available
        if !webApp.image.isEmpty {
            // Load background image from bundle or network
            // For now, use a gradient based on the image name
            backgroundImageView.backgroundColor = gradientColor(for: webApp.image)
        }
    }

    private func gradientColor(for imageName: String) -> UIColor {
        // Create gradient colors based on image name
        switch imageName {
        case "bluegradient.jpg":
            return UIColor.systemBlue.withAlphaComponent(0.1)
        case "neutralgradient.jpg":
            return UIColor.systemGray.withAlphaComponent(0.1)
        default:
            return UIColor.systemBlue.withAlphaComponent(0.1)
        }
    }
}
```

#### 2.4 Create Web App Category Header View

**File**: `Signal/ConversationView/WebAppCategoryHeaderView.swift`

```swift
class WebAppCategoryHeaderView: UITableViewHeaderFooterView {
    private let titleLabel = UILabel()
    private let iconImageView = UIImageView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundView = UIView()
        backgroundView?.backgroundColor = Theme.backgroundColor

        titleLabel.font = .ows_dynamicTypeHeadline
        titleLabel.textColor = Theme.primaryTextColor

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = Theme.accentColor

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)

        iconImageView.autoSetDimensions(to: CGSize(width: 20, height: 20))
        iconImageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 12)

        titleLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 8)
        titleLabel.autoPinEdge(.top, to: .top, of: iconImageView)
        titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)
        titleLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
    }

    func configure(with category: WebAppCategory) {
        titleLabel.text = category.name

        if let icon = UIImage(systemName: category.icon) {
            iconImageView.image = icon
        } else {
            iconImageView.image = UIImage(systemName: "folder.fill")
        }
    }
}
```

### Step 3: Create Web View Controller

#### 3.1 Create Web App Web View Controller

**File**: `Signal/ConversationView/WebAppWebViewController.swift`

```swift
class WebAppWebViewController: UIViewController {
    private let webApp: WebApp
    private let webView = WKWebView()
    private let progressView = UIProgressView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    init(webApp: WebApp) {
        self.webApp = webApp
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupWebView()
        loadWebApp()
    }

    private func setupUI() {
        title = webApp.name
        view.backgroundColor = .white

        // Navigation bar setup
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshWebApp)
        )

        // Progress view
        progressView.progressTintColor = Theme.accentColor
        progressView.trackTintColor = Theme.backgroundColor

        // Loading indicator
        loadingIndicator.hidesWhenStopped = true

        // Layout
        view.addSubview(progressView)
        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        progressView.autoPinEdge(toSuperviewEdge: .top)
        progressView.autoPinEdgesToSuperviewHorizontalEdges()
        progressView.autoSetDimension(.height, toSize: 2)

        webView.autoPinEdge(.top, to: .bottom, of: progressView)
        webView.autoPinEdgesToSuperviewSafeArea()

        loadingIndicator.autoCenterInSuperview()
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        // Add progress observer
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
    }

    private func loadWebApp() {
        guard let url = URL(string: "https://\(webApp.entry)") else {
            showError(WebAppsError.invalidURL)
            return
        }

        loadingIndicator.startAnimating()

        let request = URLRequest(url: url)
        webView.load(request)
    }

    @objc private func refreshWebApp() {
        webView.reload()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress == 1
        }
    }
}

extension WebAppWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        showError(error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Check if URL is permitted based on urlsPermitted patterns
        if let url = navigationAction.request.url {
            let isPermitted = webApp.urlsPermitted.contains { pattern in
                // Simple pattern matching - could be enhanced with regex
                return url.absoluteString.contains(pattern.replacingOccurrences(of: "\\*", with: ""))
            }

            if !isPermitted {
                // Open in external browser
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }
}
```

### Step 4: Integrate with Main Tab View

#### 4.1 Update Main Tab View Controller

**File**: `Signal/ConversationView/MainTabViewController.swift`

Add the web apps tab to the existing tab bar:

```swift
private func setupTabs() {
    // Existing tabs...

    // Add Web Apps tab
    let webAppsListVC = WebAppsListViewController(webAppsService: webAppsService)
    let webAppsNavController = OWSNavigationController(rootViewController: webAppsListVC)
    webAppsNavController.tabBarItem = WebAppsTabBarItem()

    viewControllers = [
        // Existing view controllers...
        webAppsNavController
    ]
}
```

#### 4.2 Update Tab Bar Configuration

**File**: `Signal/ConversationView/MainTabViewController.swift`

Ensure the tab bar can accommodate the new tab:

```swift
private func configureTabBar() {
    tabBar.tintColor = Theme.accentColor
    tabBar.unselectedItemTintColor = Theme.secondaryTextColor

    // Ensure tab bar can handle 5 tabs
    if #available(iOS 15.0, *) {
        tabBar.scrollEdgeAppearance = tabBar.standardAppearance
    }
}
```

### Step 5: Handle Navigation and State Management

#### 5.1 Create Web Apps Coordinator

**File**: `Signal/ConversationView/WebAppsCoordinator.swift`

```swift
protocol WebAppsCoordinatorDelegate: AnyObject {
    func webAppsCoordinator(_ coordinator: WebAppsCoordinator, didSelectWebApp webApp: WebApp)
    func webAppsCoordinatorDidRequestRefresh(_ coordinator: WebAppsCoordinator)
}

class WebAppsCoordinator {
    private weak var delegate: WebAppsCoordinatorDelegate?
    private let webAppsService: WebAppsServiceProtocol
    private let navigationController: UINavigationController

    init(delegate: WebAppsCoordinatorDelegate, webAppsService: WebAppsServiceProtocol, navigationController: UINavigationController) {
        self.delegate = delegate
        self.webAppsService = webAppsService
        self.navigationController = navigationController
    }

    func start() {
        let listVC = WebAppsListViewController(webAppsService: webAppsService)
        listVC.delegate = self
        navigationController.pushViewController(listVC, animated: false)
    }

    func showWebApp(_ webApp: WebApp) {
        let webVC = WebAppWebViewController(webApp: webApp)
        navigationController.pushViewController(webVC, animated: true)
    }
}

extension WebAppsCoordinator: WebAppsListViewControllerDelegate {
    func webAppsListViewController(_ controller: WebAppsListViewController, didSelectWebApp webApp: WebApp) {
        delegate?.webAppsCoordinator(self, didSelectWebApp: webApp)
    }

    func webAppsListViewControllerDidRequestRefresh(_ controller: WebAppsListViewController) {
        delegate?.webAppsCoordinatorDidRequestRefresh(self)
    }
}
```

### Step 6: Error Handling and Edge Cases

#### 6.1 Define Error Types

**File**: `SignalServiceKit/Account/WebAppsError.swift`

```swift
enum WebAppsError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case invalidURL
    case cacheError
    case noWebAppsAvailable

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidURL:
            return "Invalid web app URL"
        case .cacheError:
            return "Failed to cache web apps"
        case .noWebAppsAvailable:
            return "No web apps available"
        }
    }
}
```

#### 6.2 Create Empty State View

**File**: `Signal/ConversationView/EmptyStateView.swift`

```swift
class EmptyStateView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = Theme.backgroundColor

        imageView.image = UIImage(systemName: "globe")
        imageView.tintColor = Theme.secondaryTextColor
        imageView.contentMode = .scaleAspectFit

        titleLabel.text = "No Web Apps Available"
        titleLabel.font = .ows_dynamicTypeTitle2
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        messageLabel.text = "Check your internet connection and try again."
        messageLabel.font = .ows_dynamicTypeBody
        messageLabel.textColor = Theme.secondaryTextColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        retryButton.setTitle("Retry", for: .normal)
        retryButton.setTitleColor(Theme.accentColor, for: .normal)
        retryButton.titleLabel?.font = .ows_dynamicTypeBody

        addSubview(imageView)
        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(retryButton)

        imageView.autoSetDimensions(to: CGSize(width: 80, height: 80))
        imageView.autoCenterInSuperview()

        titleLabel.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 16)
        titleLabel.autoPinEdgesToSuperviewHorizontalEdges(withInset: 32)

        messageLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 8)
        messageLabel.autoPinEdgesToSuperviewHorizontalEdges(withInset: 32)

        retryButton.autoPinEdge(.top, to: .bottom, of: messageLabel, withOffset: 24)
        retryButton.autoCenterInSuperview()
    }

    func configure(retryAction: @escaping () -> Void) {
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        self.retryAction = retryAction
    }

    private var retryAction: (() -> Void)?

    @objc private func retryTapped() {
        retryAction?()
    }
}
```

### Step 7: Search Functionality

#### 7.1 Implement Search in Web Apps List

**File**: `Signal/ConversationView/WebAppsListViewController.swift`

Add search functionality:

```swift
extension WebAppsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else {
            isSearching = false
            filteredCategories = categories
            tableView.reloadData()
            return
        }

        isSearching = true
        let searchResults = webAppsService.searchWebApps(query: searchText)

        // Group search results by category
        let grouped = Dictionary(grouping: searchResults) { $0.category }
        filteredCategories = grouped.map { category, apps in
            WebAppCategory(
                name: category,
                apps: apps.sorted { $0.name < $1.name },
                icon: WebAppsConfig.categoryIcons[category] ?? "app.fill"
            )
        }.sorted { $0.name < $1.name }

        tableView.reloadData()
    }
}
```

### Step 8: Table View Data Source and Delegate

#### 8.1 Implement Table View Methods

**File**: `Signal/ConversationView/WebAppsListViewController.swift`

```swift
extension WebAppsListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return filteredCategories.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredCategories[section].apps.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WebAppCell", for: indexPath) as! WebAppCell
        let webApp = filteredCategories[indexPath.section].apps[indexPath.row]
        cell.configure(with: webApp)
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "CategoryHeader") as! WebAppCategoryHeaderView
        let category = filteredCategories[section]
        headerView.configure(with: category)
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let webApp = filteredCategories[indexPath.section].apps[indexPath.row]
        let webVC = WebAppWebViewController(webApp: webApp)
        navigationController?.pushViewController(webVC, animated: true)
    }
}
```

## Testing Checklist

- [ ] Web apps API endpoint is accessible and returns valid JSON
- [ ] Web apps are fetched and cached correctly
- [ ] Web apps list displays in tab bar
- [ ] Web apps are grouped by category correctly
- [ ] Search functionality works for app names, descriptions, and categories
- [ ] Web apps open in webview correctly
- [ ] URL permission checking works for external links
- [ ] Progress indicator shows during web app loading
- [ ] Error states are handled gracefully
- [ ] Empty state is shown when no web apps are available
- [ ] Pull-to-refresh updates the web apps list
- [ ] Offline caching works correctly
- [ ] Web apps with different types (sublist, rss) are handled appropriately
- [ ] Navigation between web apps and main app works smoothly
- [ ] Web apps respect the urlsPermitted patterns

## API Integration Requirements

- Ensure `https://my.homesteadheeritage.org/api/v2/webapps.php` is accessible
- Verify JSON response format matches expected structure
- Handle CORS if needed for webview loading
- Implement proper error handling for API failures
- Consider rate limiting and caching strategies

## Dependencies

- `SignalServiceKit` - For network requests and data storage
- `SignalUI` - For UI components and theming
- `PromiseKit` - For async operations
- `WebKit` - For webview functionality
- `PureLayout` - For auto layout constraints

## Future Enhancements

1. **Offline Support**: Cache web app content for offline viewing
2. **Favorites**: Allow users to favorite frequently used web apps
3. **Recent Apps**: Show recently accessed web apps
4. **Custom Categories**: Allow users to create custom categories
5. **App Icons**: Support custom app icons from the API
6. **Deep Linking**: Support deep links from web apps back to Signal
7. **Analytics**: Track web app usage for optimization
8. **Push Notifications**: Support notifications from web apps
9. **SSO Integration**: Use SSO tokens for authenticated web app access
10. **Performance Optimization**: Implement lazy loading and image caching

## Security Considerations

- Validate all URLs before opening in webview
- Implement proper URL permission checking
- Sanitize web app data from API
- Handle potential XSS attacks in webview content
- Implement proper certificate pinning for API calls
- Consider implementing Content Security Policy for webviews
