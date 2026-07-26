//
//  PokemonDataManager.swift
//  poketmon
//
//  pokemon_data.json을 Codable로 디코딩하여 649종 포켓몬 목록 제공
//  스프라이트 폴더 존재 여부로 사용 가능 여부 판별
//

import Foundation

// MARK: - 데이터 모델

/// 앱 표시 언어 (번들 로컬라이제이션 해석 결과 — ko/ja 외에는 en 폴백)
enum AppLanguage {
    static let code: String = Bundle.main.preferredLocalizations.first ?? "en"
}

struct PokemonData: Codable, Identifiable {
    let id: Int
    let name: String
    let nameKo: String
    let nameJa: String
    let gen: Int
    let types: [String]
    let isLegendary: Bool
    let isMythical: Bool

    /// 시스템 언어에 맞는 표시 이름 (한국어/일본어 외에는 영어)
    var localizedName: String {
        switch AppLanguage.code {
        case "ko": return nameKo
        case "ja": return nameJa
        default: return name
        }
    }

    /// 도감 번호 문자열 (#025)
    var displayNumber: String {
        String(format: "#%03d", id)
    }

    /// 4자리 ID 문자열 (0025) — 리소스 경로용
    var idString: String {
        String(format: "%04d", id)
    }
}

// MARK: - 매니저

final class PokemonDataManager {

    /// 전체 649종 포켓몬 목록
    let allPokemon: [PokemonData]

    /// 스프라이트가 있는 포켓몬 ID 집합
    let availableIDs: Set<Int>

    /// 기본 포켓몬 ID (피카츄)
    static let defaultPokemonID = 25

    init() {
        // pokemon_data.json 로드 (여러 경로 시도)
        let jsonURL = Self.findJSON()
        if let url = jsonURL,
           let data = try? Data(contentsOf: url),
           let pokemon = try? JSONDecoder().decode([PokemonData].self, from: data) {
            self.allPokemon = pokemon
        } else {
            self.allPokemon = []
        }

        // 스프라이트 폴더 존재 여부로 사용 가능 판별
        var available = Set<Int>()
        for pokemon in allPokemon {
            if SpriteSheet.spriteFileURL(pokemonID: pokemon.id, fileName: "AnimData.xml") != nil {
                available.insert(pokemon.id)
            }
        }
        self.availableIDs = available
    }

    private static func findJSON() -> URL? {
        // 1순위: 번들 루트
        if let url = Bundle.main.url(forResource: "pokemon_data", withExtension: "json") {
            return url
        }
        // 2순위: Resources 서브디렉토리
        if let url = Bundle.main.url(forResource: "pokemon_data", withExtension: "json", subdirectory: "Resources") {
            return url
        }
        // 3순위: 번들 리소스 경로에서 직접 탐색
        if let resourceURL = Bundle.main.resourceURL {
            let candidates = [
                resourceURL.appendingPathComponent("pokemon_data.json"),
                resourceURL.appendingPathComponent("Resources/pokemon_data.json"),
            ]
            for url in candidates {
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    /// 포켓몬 사용 가능 여부
    func isAvailable(_ id: Int) -> Bool {
        availableIDs.contains(id)
    }

    /// ID로 포켓몬 조회
    func pokemon(id: Int) -> PokemonData? {
        allPokemon.first { $0.id == id }
    }

    // MARK: - 필터링

    /// 세대별 포켓몬
    func pokemon(gen: Int) -> [PokemonData] {
        allPokemon.filter { $0.gen == gen }
    }

    /// 세대 + 타입 필터 (OR 조건: 선택된 타입 중 하나라도 가진 포켓몬)
    func pokemon(gen: Int, types: Set<String>) -> [PokemonData] {
        let genFiltered = pokemon(gen: gen)
        if types.isEmpty { return genFiltered }
        return genFiltered.filter { pokemon in
            !types.isDisjoint(with: pokemon.types)
        }
    }

    /// 이름(영문/한글/일본어)/번호 검색 (전체 세대 대상, 세대/타입 필터 무시)
    func search(query: String) -> [PokemonData] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allPokemon.filter { pokemon in
            pokemon.name.lowercased().contains(q)
            || pokemon.nameKo.contains(q)
            || pokemon.nameJa.contains(q)
            || String(pokemon.id).contains(q)
            || pokemon.displayNumber.contains(q)
        }
    }

    // MARK: - Portrait

    /// Portrait 이미지 번들 URL
    func portraitURL(for pokemonID: Int) -> URL? {
        let idString = String(format: "%04d", pokemonID)
        // Portraits 서브디렉토리 우선, 번들 루트 폴백 (fileSystemSynchronizedGroups가 평탄화할 수 있음)
        if let url = Bundle.main.url(forResource: idString, withExtension: "png", subdirectory: "Portraits") {
            return url
        }
        return Bundle.main.url(forResource: idString, withExtension: "png")
    }
}
