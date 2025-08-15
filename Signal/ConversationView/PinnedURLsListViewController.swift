//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit

class PinnedURLsListViewController: UIViewController {
    private let pinnedURLsService: PinnedURLsServiceProtocol
    private let webAppsService: WebAppsServiceProtocol
    private let tableView = UITableView()
    private let searchController = UISearchController(searchResultsController: nil)

    private var pinnedURLsByWebApp: [String: [PinnedURL]] = [:]
    private var filteredPinnedURLs: [PinnedURL] = []
    private var isSearching = false

    init(pinnedURLsService: PinnedURLsServiceProtocol, webAppsService: WebAppsServiceProtocol) {
        self.pinnedURLsService = pinnedURLsService
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
        loadPinnedURLs()
    }

    private func setupUI() {
        title = "Bookmarks"
        view.backgroundColor = Theme.backgroundColor

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PinnedURLCell.self, forCellReuseIdentifier: "PinnedURLCell")
        tableView.register(PinnedURLSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Bookmarks"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    private func loadPinnedURLs() {
        pinnedURLsByWebApp = pinnedURLsService.getPinnedURLsByWebApp()
        tableView.reloadData()
    }

    private func filterPinnedURLs(query: String) {
        if query.isEmpty {
            isSearching = false
            loadPinnedURLs()
        } else {
            isSearching = true
            filteredPinnedURLs = pinnedURLsService.searchPinnedURLs(query: query)
            tableView.reloadData()
        }
    }
}

extension PinnedURLsListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        if isSearching {
            return 1
        }
        return pinnedURLsByWebApp.keys.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching {
            return filteredPinnedURLs.count
        }
        let webAppEntry = Array(pinnedURLsByWebApp.keys.sorted())[section]
        return pinnedURLsByWebApp[webAppEntry]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PinnedURLCell", for: indexPath) as! PinnedURLCell

        if isSearching {
            let pinnedURL = filteredPinnedURLs[indexPath.row]
            cell.configure(with: pinnedURL)
        } else {
            let webAppEntry = Array(pinnedURLsByWebApp.keys.sorted())[indexPath.section]
            let pinnedURLs = pinnedURLsByWebApp[webAppEntry] ?? []
            let pinnedURL = pinnedURLs[indexPath.row]
            cell.configure(with: pinnedURL)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if isSearching {
            return nil
        }

        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader") as! PinnedURLSectionHeaderView
        let webAppEntry = Array(pinnedURLsByWebApp.keys.sorted())[section]
        let webApp = webAppsService.getCachedWebApps()?.first { $0.entry == webAppEntry }
        headerView.configure(with: webApp?.name ?? webAppEntry)
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return isSearching ? 0 : 44
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let pinnedURL: PinnedURL
        if isSearching {
            pinnedURL = filteredPinnedURLs[indexPath.row]
        } else {
            let webAppEntry = Array(pinnedURLsByWebApp.keys.sorted())[indexPath.section]
            let pinnedURLs = pinnedURLsByWebApp[webAppEntry] ?? []
            pinnedURL = pinnedURLs[indexPath.row]
        }

        // Record access
        Task {
            await pinnedURLsService.recordAccess(for: pinnedURL.id)
        }

        // Open URL in webview
        if let url = URL(string: pinnedURL.url) {
            let webViewController = WebAppWebViewController(url: url, title: pinnedURL.title)
            navigationController?.pushViewController(webViewController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let pinnedURL: PinnedURL
            if isSearching {
                pinnedURL = filteredPinnedURLs[indexPath.row]
                filteredPinnedURLs.remove(at: indexPath.row)
            } else {
                let webAppEntry = Array(pinnedURLsByWebApp.keys.sorted())[indexPath.section]
                var pinnedURLs = pinnedURLsByWebApp[webAppEntry] ?? []
                pinnedURL = pinnedURLs[indexPath.row]
                pinnedURLs.remove(at: indexPath.row)
                pinnedURLsByWebApp[webAppEntry] = pinnedURLs
            }

            Task {
                try await pinnedURLsService.unpinURL(pinnedURL.id)
            }

            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
}

extension PinnedURLsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterPinnedURLs(query: searchController.searchBar.text ?? "")
    }
}
