import Cocoa

/// Sheet for promoting a transient document into the library (P0-2).
final class SaveToLibrarySheetController: NSViewController {
    var onSubmit: ((TransientStore.PromoteFields) -> Void)?
    var onCancel: (() -> Void)?

    private let titleField = NSTextField(string: "")
    private let authorsField = NSTextField(string: "")
    private let yearField = NSTextField(string: "")
    private let venueField = NSTextField(string: "")
    private let categoryField = NSPopUpButton(frame: .zero, pullsDown: false)

    private let initial: TransientStore.PromoteFields
    private let categories: [String]

    init(fields: TransientStore.PromoteFields, categories: [String]) {
        self.initial = fields
        self.categories = categories.isEmpty ? ["未分类"] : categories
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 280))
        self.view = root

        let grid = NSGridView(views: [
            [label("标题"), titleField],
            [label("作者"), authorsField],
            [label("年份"), yearField],
            [label("来源"), venueField],
            [label("分类"), categoryField]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        root.addSubview(grid)

        titleField.stringValue = initial.title
        authorsField.stringValue = initial.authors
        authorsField.placeholderString = "作者（未识别）"
        yearField.stringValue = initial.year
        yearField.placeholderString = "年份"
        venueField.stringValue = initial.venue
        venueField.placeholderString = "来源，如 NeurIPS"
        categoryField.removeAllItems()
        categoryField.addItems(withTitles: categories)
        if let idx = categories.firstIndex(of: initial.category) {
            categoryField.selectItem(at: idx)
        } else {
            categoryField.selectItem(at: 0)
        }

        let save = NSButton(title: "存入", target: self, action: #selector(saveClicked))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(buttons)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    @objc private func saveClicked() {
        let fields = TransientStore.PromoteFields(
            title: titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: authorsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            year: yearField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            venue: venueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            category: categoryField.titleOfSelectedItem ?? initial.category
        )
        onSubmit?(fields)
    }

    @objc private func cancelClicked() {
        onCancel?()
    }
}
