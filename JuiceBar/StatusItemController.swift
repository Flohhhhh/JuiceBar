import AppKit
import Combine
import Foundation

@MainActor
final class StatusItemController: NSObject {
    private let viewModel: BatteryMenuViewModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let infoItem = NSMenuItem()
    private let infoView = BatteryMenuInfoView()
    private let showChargingWattageItem = NSMenuItem(
        title: "Show Charging Wattage in Menu Bar",
        action: #selector(toggleShowChargingWattageInMenuBar),
        keyEquivalent: ""
    )
    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: BatteryMenuViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configureMenu()
        bindViewModel()
        updateInterface()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.appearsDisabled = false
    }

    private func configureMenu() {
        sizeInfoView()
        infoItem.view = infoView
        menu.addItem(infoItem)
        menu.addItem(.separator())

        showChargingWattageItem.target = self
        menu.addItem(showChargingWattageItem)
        menu.addItem(.separator())

        refreshItem.target = self
        menu.addItem(refreshItem)

        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateInterface()
                }
            }
            .store(in: &cancellables)
    }

    private func updateInterface() {
        statusItem.isVisible = viewModel.showsMenuBarItem
        showChargingWattageItem.state = viewModel.showsChargingWattageInMenuBar ? .on : .off
        updateButton()
        updateInfoView()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        button.attributedTitle = NSAttributedString(string: viewModel.displayText, attributes: attributes)

        if viewModel.showsChargingBolt {
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
        } else {
            button.image = nil
        }
    }

    private func updateInfoView() {
        infoView.update(
            headline: viewModel.headlineText,
            percentage: "\(viewModel.percentageText) battery",
            status: "Status: \(viewModel.statusText)",
            dataSource: "Data Source: \(viewModel.dataSourceText)",
            chargingPower: viewModel.chargingPowerText
        )
        sizeInfoView()
    }

    private func sizeInfoView() {
        let size = infoView.intrinsicContentSize
        infoView.frame = NSRect(origin: .zero, size: size)
        infoView.layoutSubtreeIfNeeded()
    }

    @objc private func refresh() {
        viewModel.refresh()
    }

    @objc private func toggleShowChargingWattageInMenuBar() {
        viewModel.setShowsChargingWattageInMenuBar(!viewModel.showsChargingWattageInMenuBar)
    }

    @objc private func quit() {
        viewModel.quit()
    }
}

private final class BatteryMenuInfoView: NSView {
    private enum Metrics {
        static let width: CGFloat = 286
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 12
        static let sectionSpacing: CGFloat = 12
        static let lineSpacing: CGFloat = 3
        static let dividerSpacing: CGFloat = 10
        static let dividerHeight: CGFloat = 1
    }

    private let headlineLabel = BatteryMenuInfoView.makePrimaryLabel()
    private let percentageLabel = BatteryMenuInfoView.makeSecondaryLabel()
    private let divider = NSBox()
    private let infoHeader = BatteryMenuInfoView.makeHeaderLabel("Info")
    private let statusLabel = BatteryMenuInfoView.makeSecondaryLabel()
    private let dataSourceLabel = BatteryMenuInfoView.makeSecondaryLabel()
    private let chargingPowerLabel = BatteryMenuInfoView.makeSecondaryLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        frame.size = intrinsicContentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(headline: String, percentage: String, status: String, dataSource: String, chargingPower: String?) {
        headlineLabel.stringValue = headline
        percentageLabel.stringValue = percentage
        statusLabel.stringValue = status
        dataSourceLabel.stringValue = dataSource
        chargingPowerLabel.stringValue = chargingPower ?? ""
        chargingPowerLabel.isHidden = chargingPower == nil
        invalidateIntrinsicContentSize()
        frame.size = intrinsicContentSize
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let contentWidth = Metrics.width - (Metrics.horizontalInset * 2)
        let headlineHeight = headlineLabel.sizeThatFits(width: contentWidth).height
        let percentageHeight = percentageLabel.sizeThatFits(width: contentWidth).height
        let statusHeight = statusLabel.sizeThatFits(width: contentWidth).height
        let sourceHeight = dataSourceLabel.sizeThatFits(width: contentWidth).height
        let chargingPowerHeight = chargingPowerLabel.isHidden
            ? 0
            : chargingPowerLabel.sizeThatFits(width: contentWidth).height + Metrics.lineSpacing

        let totalHeight =
            Metrics.verticalInset
            + headlineHeight
            + Metrics.lineSpacing
            + percentageHeight
            + Metrics.dividerSpacing
            + Metrics.dividerHeight
            + Metrics.sectionSpacing
            + infoHeader.intrinsicContentSize.height
            + Metrics.lineSpacing
            + statusHeight
            + Metrics.lineSpacing
            + sourceHeight
            + chargingPowerHeight
            + Metrics.verticalInset

        return NSSize(width: Metrics.width, height: ceil(totalHeight))
    }

    override func layout() {
        super.layout()

        let contentWidth = bounds.width - (Metrics.horizontalInset * 2)
        var y = bounds.height - Metrics.verticalInset

        y = place(headlineLabel, atY: y, width: contentWidth)
        y -= Metrics.lineSpacing
        y = place(percentageLabel, atY: y, width: contentWidth)
        y -= Metrics.dividerSpacing
        y = placeDivider(atY: y, width: contentWidth)
        y -= Metrics.sectionSpacing
        y = place(infoHeader, atY: y, width: contentWidth)
        y -= Metrics.lineSpacing
        y = place(statusLabel, atY: y, width: contentWidth)
        y -= Metrics.lineSpacing
        y = place(dataSourceLabel, atY: y, width: contentWidth)

        if !chargingPowerLabel.isHidden {
            y -= Metrics.lineSpacing
            _ = place(chargingPowerLabel, atY: y, width: contentWidth)
        }
    }

    private func setupView() {
        divider.boxType = .separator

        chargingPowerLabel.isHidden = true

        for label in [headlineLabel, percentageLabel, infoHeader, statusLabel, dataSourceLabel, chargingPowerLabel] {
            addSubview(label)
        }
        addSubview(divider)
    }

    @discardableResult
    private func place(_ label: NSTextField, atY maxY: CGFloat, width: CGFloat) -> CGFloat {
        let size = label.sizeThatFits(width: width)
        let minY = maxY - size.height
        label.frame = NSRect(x: Metrics.horizontalInset, y: minY, width: width, height: size.height)
        return minY
    }

    @discardableResult
    private func placeDivider(atY maxY: CGFloat, width: CGFloat) -> CGFloat {
        let minY = maxY - Metrics.dividerHeight
        divider.frame = NSRect(x: Metrics.horizontalInset, y: minY, width: width, height: Metrics.dividerHeight)
        return minY
    }

    private static func makeHeaderLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private static func makePrimaryLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.textColor = .labelColor
        return label
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }
}

private extension NSTextField {
    func sizeThatFits(width: CGFloat) -> NSSize {
        let size = CGSize(width: width, height: .greatestFiniteMagnitude)
        return cell?.cellSize(forBounds: NSRect(origin: .zero, size: size)) ?? .zero
    }
}
