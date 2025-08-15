//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit



class WebAppsListViewController: UIViewController {
    private let webAppsService: WebAppsServiceProtocol
    private let userInfoStore: SSOUserInfoStore
    private let searchController = UISearchController(searchResultsController: nil)
    
    // UI Components
    let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let emptyStateView = EmptyStateView()

    // Data
    private var allWebApps: [WebApp] = []
    private var allCategories: [WebAppCategory] = []
    private var filteredCategories: [WebAppCategory] = []
    private var isSearching = false



    init(webAppsService: WebAppsServiceProtocol, userInfoStore: SSOUserInfoStore = SSOUserInfoStoreImpl()) {
        self.webAppsService = webAppsService
        self.userInfoStore = userInfoStore
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
        title = "Portal"
        view.backgroundColor = Theme.backgroundColor

        // Initialize data arrays
        allCategories = []
        allWebApps = []
        filteredCategories = []

        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(WebAppCell.self, forCellReuseIdentifier: "WebAppCell")
        tableView.register(WebAppCategoryHeaderView.self, forHeaderFooterViewReuseIdentifier: "CategoryHeader")

        // Setup refresh control
        refreshControl.addTarget(self, action: #selector(refreshWebApps), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // Setup empty state
        emptyStateView.configure { [weak self] in
            self?.loadWebApps()
        }

        // Layout
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(loadingIndicator)

        tableView.autoPinEdgesToSuperviewEdges()
        emptyStateView.autoPinEdgesToSuperviewEdges()
        loadingIndicator.autoCenterInSuperview()

        emptyStateView.isHidden = true
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search apps..."
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

        // Initialize with empty arrays to prevent crashes
        allCategories = []
        allWebApps = []
        filteredCategories = []

        // Fetch categorized web apps first, then global allow list
        let userRoles = userInfoStore.getUserRoles()
        _ = webAppsService.fetchWebAppsCategorized(userRoles: userRoles)
            .then { [weak self] categories -> Promise<[GlobalAllowEntry]> in
                self?.allCategories = categories
                // Also store individual webapps for search functionality
                self?.allWebApps = categories.flatMap { $0.apps }
                return self?.webAppsService.fetchGlobalAllowList() ?? Promise.value([])
            }
            .done { [weak self] globalAllowList in
                self?.updateUI()
                Logger.info("📋 Loaded \(self?.allCategories.count ?? 0) categories with \(self?.allWebApps.count ?? 0) total web apps and \(globalAllowList.count) global allow entries")
            }
            .catch { [weak self] error in
                self?.showError(error)
            }
            .ensure { [weak self] in
                self?.loadingIndicator.stopAnimating()
                self?.refreshControl.endRefreshing()
            }
    }

    private func updateUI() {
        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isSearching {
                // Show filtered results
                self.tableView.reloadData()
            } else {
                // Use the categorized webapps that were already filtered by user roles
                self.filteredCategories = self.allCategories
                self.tableView.reloadData()
            }

            let totalApps = self.filteredCategories.flatMap { $0.apps }
            self.emptyStateView.isHidden = !totalApps.isEmpty
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension WebAppsListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return filteredCategories.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < filteredCategories.count else { return 0 }
        return filteredCategories[section].apps.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < filteredCategories.count else { return nil }
        return filteredCategories[section].name
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < filteredCategories.count else { return nil }
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "CategoryHeader") as! WebAppCategoryHeaderView
        return headerView
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WebAppCell", for: indexPath) as! WebAppCell
        
        guard indexPath.section < filteredCategories.count,
              indexPath.row < filteredCategories[indexPath.section].apps.count else {
            // Return a default cell if data is not available
            return cell
        }
        
        let webApp = filteredCategories[indexPath.section].apps[indexPath.row]
        cell.configure(with: webApp)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.section < filteredCategories.count,
              indexPath.row < filteredCategories[indexPath.section].apps.count else {
            return
        }

        let webApp = filteredCategories[indexPath.section].apps[indexPath.row]
        let webVC = WebAppWebViewController(webApp: webApp, webAppsService: webAppsService, userInfoStore: userInfoStore)
        navigationController?.pushViewController(webVC, animated: true)
    }
}

extension WebAppsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else {
            isSearching = false
            // Use the categorized webapps that were already filtered by user roles
            filteredCategories = allCategories
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
            return
        }

        isSearching = true
        let userRoles = userInfoStore.getUserRoles()
        let searchResults = webAppsService.searchWebApps(query: searchText, userRoles: userRoles)
        
        // Group search results by category
        let grouped = Dictionary(grouping: searchResults) { $0.category }
        filteredCategories = grouped.map { category, apps in
            WebAppCategory(
                name: category,
                apps: apps.sorted { $0.name < $1.name }
            )
        }.sorted { $0.name < $1.name }

        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }
} 
