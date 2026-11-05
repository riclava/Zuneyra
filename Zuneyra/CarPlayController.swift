#if os(iOS)
import CarPlay
import Observation

@MainActor final class CarPlayController: NSObject, CPNowPlayingTemplateObserver {
    let store: PlayerStore
    private weak var interface: CPInterfaceController?
    private var lists: [ObjectIdentifier: (CPListTemplate, CarPlayRoute, Int)] = [:]
    private var roots: [CPListTemplate] = []
    private var connected = false
    private var rootReady = false
    private var displayedError: String?
    private let nowPlaying = CPNowPlayingTemplate.shared
    init(store: PlayerStore) { self.store = store }
    private var catalog: CarPlayCatalog { CarPlayCatalog(tracks: store.tracks, playlists: store.playlists, queue: store.queueState) }

    func connect(_ interface: CPInterfaceController) {
        self.interface = interface; connected = true
        roots = [(.playlists, "music.note.list"), (.favorites, "heart.fill"), (.albums, "square.stack"), (.artists, "person.2.fill")].map { (route: CarPlayRoute, symbol: String) in
            let list = makeList(route)
            list.tabTitle = catalog.title(for: route); list.tabImage = UIImage(systemName: symbol)
            return list
        }
        nowPlaying.add(self)
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = String(localized: "播放队列")
        nowPlaying.isAlbumArtistButtonEnabled = false
        interface.setRootTemplate(CPTabBarTemplate(templates: roots), animated: false) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                guard let self, self.connected else { return }
                self.rootReady = success; self.observe()
            }
        }
    }
    func refreshContentStyle() { guard connected else { return }; refresh() }
    func disconnect() {
        guard connected else { return }
        connected = false; rootReady = false
        nowPlaying.remove(self)
        interface = nil; lists.removeAll(); roots.removeAll()
        // Stop before the audio route falls back to the phone speaker. Reconnect never resumes.
        store.pause()
    }
    private func observe() {
        guard connected else { return }
        withObservationTracking {
            _ = store.tracks; _ = store.playlists; _ = store.queueState
            _ = store.current; _ = store.isPlaying; _ = store.isLoading
            _ = store.isManaging; _ = store.errorMessage; _ = store.queueNotice
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in await Task.yield(); self?.observe() }
        }
    }
    private func refresh() {
        guard connected else { return }
        if let interface {
            let live = Set((interface.templates + roots).map(ObjectIdentifier.init))
            lists = lists.filter { live.contains($0.key) }
        }
        for (_, (list, route, page)) in lists { update(list, route: route, page: page) }
        let shuffle = CPNowPlayingShuffleButton { [weak self] _ in self?.store.toggleShuffle() }
        let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in self?.store.cycleRepeatMode() }
        shuffle.isEnabled = !store.isManaging; repeatButton.isEnabled = !store.isManaging
        nowPlaying.updateNowPlayingButtons([shuffle, repeatButton])
        nowPlaying.isUpNextButtonEnabled = !store.queueState.canonical.isEmpty
        if rootReady, let error = store.errorMessage, error != displayedError, interface?.presentedTemplate == nil {
            displayedError = error
            let alert = CPAlertTemplate(titleVariants: [error], actions: [CPAlertAction(title: String(localized: "好"), style: .default) { [weak self] _ in
                self?.store.errorMessage = nil
                self?.interface?.dismissTemplate(animated: true, completion: nil)
            }])
            interface?.presentTemplate(alert, animated: true, completion: nil)
        }
        if store.errorMessage == nil { displayedError = nil }
    }
    private func makeList(_ route: CarPlayRoute) -> CPListTemplate {
        let list = CPListTemplate(title: catalog.title(for: route), sections: [])
        list.emptyViewTitleVariants = [String(localized: "这里还没有音乐")]
        list.emptyViewSubtitleVariants = [String(localized: "请在 iPhone 导入音乐或整理歌单。")]
        list.trailingNavigationBarButtons = [CPBarButton(title: String(localized: "正在播放")) { [weak self] _ in self?.showNowPlaying() }]
        lists[ObjectIdentifier(list)] = (list, route, 0)
        update(list, route: route, page: 0)
        return list
    }
    private func update(_ list: CPListTemplate, route: CarPlayRoute, page: Int) {
        let model = catalog
        let size = max(1, min(80, CPListTemplate.maximumItemCount - 2))
        let page = CarPlayPage.make(rows: model.rows(for: route), index: page, size: size)
        lists[ObjectIdentifier(list)] = (list, route, page.index)
        list.emptyViewTitleVariants = [store.isLoading ? String(localized: "正在读取音乐库…") : String(localized: "这里还没有音乐")]
        var items: [CPListItem] = page.rows.map { row in
            let item = CPListItem(text: row.title, detailText: row.detail, image: listImage(row.trackID == nil ? "music.note.list" : "music.note"))
            item.isEnabled = !store.isLoading && !store.isManaging
            if case .queueEntry(let id) = row.action { item.isPlaying = id == store.queueState.currentID && store.isPlaying }
            else if case .play(let id, _) = row.action { item.isPlaying = id == store.current?.id && store.isPlaying }
            if case .open = row.action { item.accessoryType = .disclosureIndicator }
            item.handler = { [weak self] _, completion in
                defer { completion() }
                guard let self, self.connected else { return }
                if case .open(let route) = row.action { self.push(self.makeList(route)) }
                else if self.store.performCarPlayAction(row.action) { self.showNowPlaying() }
            }
            return item
        }
        if let previous = page.previous { items.insert(pageItem(String(localized: "上一页"), list: list, route: route, page: previous), at: 0) }
        if let next = page.next { items.append(pageItem(String(localized: "下一页"), list: list, route: route, page: next)) }
        list.trailingNavigationBarButtons.first?.isEnabled = store.current != nil || !store.queueState.canonical.isEmpty
        list.updateSections([CPListSection(items: items)])
    }
    private func listImage(_ symbol: String) -> UIImage? {
        let traits = interface?.carTraitCollection ?? UITraitCollection(userInterfaceStyle: .dark)
        return UIImage(systemName: symbol)?.withTintColor(UIColor.secondaryLabel.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
    }
    private func pageItem(_ title: String, list: CPListTemplate, route: CarPlayRoute, page: Int) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil)
        item.handler = { [weak self, weak list] _, done in
            defer { done() }
            guard let self, self.connected, let list else { return }
            self.update(list, route: route, page: page)
        }
        return item
    }
    private func push(_ template: CPTemplate) {
        guard connected, rootReady, interface?.topTemplate !== template else { return }
        if interface?.templates.contains(where: { $0 === template }) == true {
            interface?.pop(to: template, animated: true, completion: nil)
        } else {
            interface?.pushTemplate(template, animated: true, completion: nil)
        }
    }
    private func showNowPlaying() {
        guard store.current != nil else { showQueue(); return }
        push(nowPlaying)
    }
    private func showQueue() {
        if let existing = lists.values.first(where: { $0.1 == .queue && interface?.templates.contains($0.0) == true }) {
            push(existing.0)
        } else { push(makeList(.queue)) }
    }
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) { showQueue() }
}
#endif
