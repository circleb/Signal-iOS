//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit



class WebAppsListViewController: UIViewController {
    private let webAppsService: WebAppsServiceProtocol
    private let searchController = UISearchController(searchResultsController: nil)

    // UI Components
    let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let emptyStateView = EmptyStateView()

    // Data
    private var allWebApps: [WebApp] = []
    private var filteredWebApps: [WebApp] = []
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
        title = "Portal"
        view.backgroundColor = Theme.backgroundColor

        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(WebAppCell.self, forCellReuseIdentifier: "WebAppCell")

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

        // Fetch web apps first, then global allow list
        _ = webAppsService.fetchWebApps()
            .then { [weak self] webApps -> Promise<[GlobalAllowEntry]> in
                self?.allWebApps = webApps.sorted { $0.name < $1.name }
                return self?.webAppsService.fetchGlobalAllowList() ?? Promise.value([])
            }
            .done { [weak self] globalAllowList in
                self?.updateUI()
                Logger.info("📋 Loaded \(self?.allWebApps.count ?? 0) web apps and \(globalAllowList.count) global allow entries")
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
        if isSearching {
            // Show filtered results
            tableView.reloadData()
        } else {
            // Show all web apps
            filteredWebApps = allWebApps
            tableView.reloadData()
        }

        emptyStateView.isHidden = !filteredWebApps.isEmpty
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
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredWebApps.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WebAppCell", for: indexPath) as! WebAppCell
        let webApp = filteredWebApps[indexPath.row]
        cell.configure(with: webApp)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let webApp = filteredWebApps[indexPath.row]
        let webVC = WebAppWebViewController(webApp: webApp, webAppsService: webAppsService)
        navigationController?.pushViewController(webVC, animated: true)
    }
}

extension WebAppsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else {
            isSearching = false
            filteredWebApps = allWebApps
            tableView.reloadData()
            return
        }

        isSearching = true
        let searchResults = webAppsService.searchWebApps(query: searchText)
        filteredWebApps = searchResults.sorted { $0.name < $1.name }

        tableView.reloadData()
    }
} 
