//
//  PokemonDataManager.swift
//  poketmon
//
//  pokemon_data.json을 Codable로 디코딩하여 포켓몬 목록 제공 (1025종 + 메가 26종)
//  스프라이트 폴더 존재 여부로 사용 가능 여부 판별
//

import Foundation

// MARK: - 데이터 모델

/// 앱 표시 언어 (번들 로컬라이제이션 해석 결과 — ko/ja 외에는 en 폴백)
enum AppLanguage {
    static let code: String = Bundle.main.preferredLocalizations.first ?? "en"
}

// MARK: - 한글 초성 검색

enum HangulSearch {
    /// 초성 19자 (완성형 음절 초성 인덱스 순서)
    private static let choseongTable: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 완성형 한글 음절(가~힣)의 초성 추출, 음절이 아니면 nil
    private static func choseong(of char: Character) -> Character? {
        guard let scalar = char.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        return choseongTable[Int(scalar.value - 0xAC00) / (21 * 28)]
    }

    private static func isChoseongJamo(_ char: Character) -> Bool {
        choseongTable.contains(char)
    }

    /// 초성 자모가 섞인 검색어의 부분 일치 검색
    /// 초성 자모는 해당 초성을 가진 음절과, 그 외 문자는 동일 문자와 매칭
    /// 예: "ㅍㅋㅊ", "피카ㅊ" → "피카츄" 매칭
    static func matches(text: String, query: String) -> Bool {
        // 초성 자모가 없으면 일반 contains 검색과 동일하므로 건너뜀
        guard query.contains(where: isChoseongJamo) else { return false }
        let textChars = Array(text)
        let queryChars = Array(query)
        guard !queryChars.isEmpty, queryChars.count <= textChars.count else { return false }

        for start in 0...(textChars.count - queryChars.count) {
            var matched = true
            for (offset, queryChar) in queryChars.enumerated() {
                let textChar = textChars[start + offset]
                if isChoseongJamo(queryChar) {
                    if choseong(of: textChar) != queryChar {
                        matched = false
                        break
                    }
                } else if textChar != queryChar {
                    matched = false
                    break
                }
            }
            if matched { return true }
        }
        return false
    }
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

    /// 메가 진화 폼의 원본 도감 번호 (기본 폼은 nil)
    let baseID: Int?

    /// 메가 진화 폼 여부
    var isMega: Bool { baseID != nil }

    /// 시스템 언어에 맞는 표시 이름 (한국어/일본어 외에는 영어)
    var localizedName: String {
        switch AppLanguage.code {
        case "ko": return nameKo
        case "ja": return nameJa
        default: return name
        }
    }

    /// 사용자에게 보이는 도감 번호 — 메가 폼은 원본 종의 번호
    ///
    /// id는 메가 폼에서 합성 번호(20000+도감번호)이므로 표시·검색에 쓰면 안 된다.
    /// 리소스 경로에는 id(idString)를 그대로 써야 한다.
    var dexNumber: Int { baseID ?? id }

    /// 도감 번호 문자열 (#025)
    var displayNumber: String {
        String(format: "#%03d", dexNumber)
    }

    /// 4자리 ID 문자열 (0025) — 리소스 경로용
    var idString: String {
        String(format: "%04d", id)
    }

    /// 검색어 매칭 — 영문/한글/일본어 이름, 한글 초성(ㅍㅋㅊ), 도감 번호
    /// query는 소문자·공백 제거된 상태여야 함
    ///
    /// 번호 검색은 사용자에게 보이는 도감 번호(baseID)만 대상으로 한다.
    /// 메가 폼의 id는 합성 번호(20000+도감번호)라 그대로 매칭하면
    /// "2"에 메가 전체가, "6"에 메가후딘(20065)이 걸린다.
    func matches(query: String) -> Bool {
        name.lowercased().contains(query)
        || nameKo.contains(query)
        || nameJa.contains(query)
        || String(dexNumber).contains(query)
        || displayNumber.contains(query)
        || HangulSearch.matches(text: nameKo, query: query)
    }
}

// MARK: - 매니저

final class PokemonDataManager {

    /// 전체 포켓몬 목록 (기본 1025종 + 메가 26종)
    let allPokemon: [PokemonData]

    /// 스프라이트가 있는 포켓몬 ID 집합
    let availableIDs: Set<Int>

    /// 기본 포켓몬 ID (피카츄)
    static let defaultPokemonID = 25

    /// 메가 진화 탭의 gen 값 — 세대 탭(1~9)과 겹치지 않는 별도 값
    ///
    /// 메가는 종의 희귀도가 아니라 형태(form) 축이라 전설/환상 필터와 같은
    /// 레벨에 두면 필터 조합의 의미가 흐려진다. 별도 탭으로 분리했다.
    static let megaGen = 100

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

    /// 이름(영문/한글 초성 포함/일본어)/번호 검색 (전체 세대 대상, 세대/타입 필터 무시)
    func search(query: String) -> [PokemonData] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allPokemon.filter { $0.matches(query: q) }
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
