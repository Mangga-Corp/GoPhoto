//
//  PreferencesPopoverViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

final class PreferencesPopoverViewController: UIViewController {
    /// Called with the preference id when its Edit button is tapped.
    var onEdit: ((UUID) -> Void)?

    private let viewModel: PreferencesViewModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let addButton = PillButton(title: "Add")
    private let maxTableHeight: CGFloat = 320

    init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 300, height: CGFloat(viewModel.preferences.count) * 56 + 64)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface
        tableView.backgroundColor = .clear
        tableView.separatorColor = Theme.stroke
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.alwaysBounceVertical = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PreferenceCell.self, forCellReuseIdentifier: PreferenceCell.reuseID)
        addButton.addAction(UIAction { [weak self] _ in self?.addTapped() }, for: .touchUpInside)

        [tableView, addButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            addButton.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 8),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSize()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.flashScrollIndicators()
    }

    /// Fits the popover to its content (list + Add button), scrolling only when the list is long.
    private func updateSize() {
        let content = tableView.contentSize.height
        let height = min(content, maxTableHeight) + 8 + 44 + 12
        guard abs(preferredContentSize.height - height) > 0.5 else { return }
        preferredContentSize = CGSize(width: 300, height: height)
    }

    private func refresh(scrollTo row: Int? = nil) {
        tableView.reloadData()
        tableView.layoutIfNeeded()
        updateSize()
        guard let row else { return }
        DispatchQueue.main.async { [weak self] in
            self?.tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .none, animated: true)
        }
    }

    private func addTapped() {
        let alert = UIAlertController(title: "New Preference", message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "Name"
            $0.autocapitalizationType = .words
            $0.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            if let error = self.viewModel.add(name: alert?.textFields?.first?.text ?? "") {
                self.showError(error)
            } else {
                self.refresh(scrollTo: self.viewModel.preferences.count - 1)
            }
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension PreferencesPopoverViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int { viewModel.preferences.count }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        guard let cell = tv.dequeueReusableCell(withIdentifier: PreferenceCell.reuseID, for: ip) as? PreferenceCell
        else { return UITableViewCell() }
        let preference = viewModel.preferences[ip.row]
        cell.configure(name: preference.name, selected: viewModel.isSelected(at: ip.row))
        cell.onEdit = { [weak self] in self?.onEdit?(preference.id) }
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        viewModel.select(at: ip.row)
        refresh(scrollTo: ip.row)
    }
}
