//
//  PokemonSelectorView.swift
//  poketmon
//
//  포켓몬 선택기 — NSPanel + SwiftUI 구현
//  검색바 + 세대 탭 + 타입 필터 칩 + 포켓몬 그리드
//

import SwiftUI
import AppKit

// MARK: - 선택기 윈도우 컨트롤러

final class PokemonSelectorWindowController: NSObject, NSWindowDelegate {
    static let shared = PokemonSelectorWindowController()

    private var panel: NSPanel?

    /// 선택기 윈도우 열기 (이미 열려있으면 앞으로 가져오기)
    func open() {
        if let existing = panel, existing.isVisible {
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKey()
            return
        }

        panel = nil

        let newPanel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newPanel.title = String(localized: "Choose Pokémon")
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        newPanel.isMovableByWindowBackground = true
        newPanel.animationBehavior = .utilityWindow
        newPanel.isReleasedWhenClosed = false
        newPanel.delegate = self

        // 포켓몬 현재 위치의 모니터 중앙에 배치
        let petPos = PetManager.shared.stateMachine.position
        let screen = NSScreen.screens.first { $0.frame.contains(petPos) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen {
            let visible = screen.visibleFrame
            let size = newPanel.frame.size
            newPanel.setFrameOrigin(CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }

        newPanel.contentView = NSHostingView(rootView: PokemonSelectorView())

        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = newPanel
    }

    /// 선택기 윈도우 닫기
    func close() {
        panel?.close()
        panel = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        ThumbnailCache.shared.clearAll()
        panel = nil
    }
}

// MARK: - 썸네일 캐시 (스레드 안전)

private final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private var cache: [Int: NSImage] = [:]
    private let lock = NSLock()

    func get(_ id: Int) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[id]
    }

    func clearAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// 포트레이트 → 스프라이트 첫 프레임 순서로 로드 (백그라운드 스레드에서 호출)
    func loadThumbnail(for pokemonID: Int) -> NSImage? {
        if let cached = get(pokemonID) { return cached }

        let dm = PetManager.shared.pokemonDataManager
        var image: NSImage?

        // 1순위: Portrait
        if let url = dm.portraitURL(for: pokemonID) {
            image = NSImage(contentsOf: url)
        }

        // 2순위: Idle 스프라이트 첫 프레임
        if image == nil,
           let animData = AnimDataParser.parse(pokemonID: pokemonID),
           let anim = animData.animation(named: "Idle"),
           let cgImage = SpriteSheet.loadImage(pokemonID: pokemonID, fileName: "Idle-Anim.png"),
           let sheet = SpriteSheet.extract(from: cgImage, animData: anim),
           let frame = sheet.frame(direction: .down, index: 0) {
            image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        }

        if let image {
            lock.lock()
            cache[pokemonID] = image
            lock.unlock()
        }

        return image
    }
}

// MARK: - 타입 색상 정의

private let pokemonTypeColors: [String: Color] = [
    "Normal":   Color(red: 0.66, green: 0.65, blue: 0.48),
    "Fire":     Color(red: 0.93, green: 0.51, blue: 0.19),
    "Water":    Color(red: 0.39, green: 0.56, blue: 0.94),
    "Grass":    Color(red: 0.48, green: 0.78, blue: 0.30),
    "Electric": Color(red: 0.97, green: 0.82, blue: 0.17),
    "Ice":      Color(red: 0.59, green: 0.85, blue: 0.84),
    "Fighting": Color(red: 0.76, green: 0.18, blue: 0.16),
    "Poison":   Color(red: 0.64, green: 0.24, blue: 0.63),
    "Ground":   Color(red: 0.89, green: 0.75, blue: 0.40),
    "Flying":   Color(red: 0.66, green: 0.56, blue: 0.95),
    "Psychic":  Color(red: 0.98, green: 0.33, blue: 0.53),
    "Bug":      Color(red: 0.65, green: 0.73, blue: 0.10),
    "Rock":     Color(red: 0.71, green: 0.63, blue: 0.21),
    "Ghost":    Color(red: 0.45, green: 0.34, blue: 0.59),
    "Dragon":   Color(red: 0.44, green: 0.21, blue: 0.99),
    "Dark":     Color(red: 0.44, green: 0.34, blue: 0.27),
    "Steel":    Color(red: 0.72, green: 0.72, blue: 0.81),
    "Fairy":    Color(red: 0.84, green: 0.52, blue: 0.68),
]

private let allPokemonTypes = [
    "Normal", "Fire", "Water", "Grass", "Electric", "Ice",
    "Fighting", "Poison", "Ground", "Flying", "Psychic", "Bug",
    "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy",
]

// MARK: - 선택기 메인 뷰

struct PokemonSelectorView: View {
    @State private var searchText = ""
    @State private var selectedGen = 1
    @State private var activeTypes: Set<String> = []
    @State private var showLegendary = false
    @State private var showMythical = false
    @State private var selectedPokemonID: Int?

    private let dataManager = PetManager.shared.pokemonDataManager

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    /// 필터 조합 결과 (세대/타입/분류 필터 적용 후 검색어로 추가 필터)
    private var filteredPokemon: [PokemonData] {
        var base = dataManager.pokemon(gen: selectedGen, types: activeTypes)
        if showLegendary || showMythical {
            base = base.filter {
                ($0.isLegendary && showLegendary) || ($0.isMythical && showMythical)
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter { $0.matches(query: q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            genTabs
            typeChips
            Divider()
            pokemonGrid
            Divider()
            footer
        }
    }

    // MARK: - 검색바

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("Search by name or number...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 세대 탭 (2줄: 1~5세대 / 6~9세대)

    private var genTabs: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { gen in
                    genTabButton(gen: gen)
                }
            }
            HStack(spacing: 4) {
                ForEach(6...9, id: \.self) { gen in
                    genTabButton(gen: gen)
                }
                megaTabButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// 메가 진화 탭 — 세대가 아니라 형태 축이라 별도 탭으로 분리
    private var megaTabButton: some View {
        let megaGen = PokemonDataManager.megaGen
        let isActive = selectedGen == megaGen
        let count = dataManager.pokemon(gen: megaGen).count

        return Button {
            selectedGen = megaGen
        } label: {
            VStack(spacing: 2) {
                Text("Mega")
                    .font(.system(size: 12, weight: .medium))
                Text("\(count) species")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func genTabButton(gen: Int) -> some View {
        let isActive = selectedGen == gen
        let count = dataManager.pokemon(gen: gen).count

        return Button {
            selectedGen = gen
        } label: {
            VStack(spacing: 2) {
                Text("Gen \(gen)")
                    .font(.system(size: 12, weight: .medium))
                Text("\(count) species")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 타입 필터 칩

    private var typeChips: some View {
        VStack(spacing: 6) {
            chipRow(types: Array(allPokemonTypes[0..<6]))
            chipRow(types: Array(allPokemonTypes[6..<12]))
            chipRow(types: Array(allPokemonTypes[12..<18]))
            categoryChipRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// 분류 필터 칩 (전설/환상)
    private var categoryChipRow: some View {
        HStack(spacing: 6) {
            categoryChipButton(
                label: "Legendary",
                color: Color(red: 0.85, green: 0.60, blue: 0.13),
                isActive: showLegendary
            ) { showLegendary.toggle() }

            categoryChipButton(
                label: "Mythical",
                color: Color(red: 0.72, green: 0.35, blue: 0.85),
                isActive: showMythical
            ) { showMythical.toggle() }
        }
    }

    private func categoryChipButton(
        label: LocalizedStringKey,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: isActive ? "star.fill" : "star")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    isActive ? color.opacity(0.2) : Color.primary.opacity(0.04),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? color.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
                )
                .foregroundStyle(isActive ? color : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func chipRow(types: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(types, id: \.self) { type in
                typeChipButton(type: type)
            }
        }
    }

    private func typeChipButton(type: String) -> some View {
        let isActive = activeTypes.contains(type)
        let color = pokemonTypeColors[type] ?? .gray

        return Button {
            if isActive { activeTypes.remove(type) }
            else { activeTypes.insert(type) }
        } label: {
            Text(LocalizedStringKey(type))
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    isActive ? color.opacity(0.2) : Color.primary.opacity(0.04),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? color.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
                )
                .foregroundStyle(isActive ? color : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 포켓몬 그리드

    private var pokemonGrid: some View {
        ScrollView {
            let currentID = PetManager.shared.currentPokemonID
            let pokemon = filteredPokemon

            if pokemon.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text("No results")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(pokemon) { poke in
                        let isAvailable = dataManager.isAvailable(poke.id)

                        PokemonCellView(
                            pokemon: poke,
                            isSelected: selectedPokemonID == poke.id,
                            isCurrent: currentID == poke.id,
                            isAvailable: isAvailable
                        )
                        .onTapGesture {
                            guard isAvailable else { return }
                            selectedPokemonID = poke.id
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - 하단 버튼

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                PokemonSelectorWindowController.shared.close()
            }
            .keyboardShortcut(.cancelAction)

            Button("Select") {
                let id = selectedPokemonID
                PokemonSelectorWindowController.shared.close()
                if let id {
                    PetManager.shared.changePokemon(to: id)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPokemonID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 포켓몬 셀

private struct PokemonCellView: View {
    let pokemon: PokemonData
    let isSelected: Bool
    let isCurrent: Bool
    let isAvailable: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 2) {
            Text(pokemon.displayNumber)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else if isAvailable {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                }

                if !isAvailable {
                    Text("N/A")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)

            Text(pokemon.localizedName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 2)
        )
        .opacity(isAvailable ? 1 : 0.3)
        .task(id: pokemon.id) {
            guard isAvailable else { return }
            if let cached = ThumbnailCache.shared.get(pokemon.id) {
                thumbnail = cached
                return
            }
            let id = pokemon.id
            let image = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.loadThumbnail(for: id)
            }.value
            thumbnail = image
        }
    }

    private var borderColor: Color {
        if isSelected { return .accentColor.opacity(0.6) }
        if isCurrent { return .green.opacity(0.5) }
        return .clear
    }
}
