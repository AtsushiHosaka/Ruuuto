import SwiftUI

/// 投稿に付ける都市を選ぶ画面（RCNO-29）。都市を指定しないで投稿することもできる。
///
/// 一覧にない場所は「国名 + 北部・南部・東部・西部・中部」の地域で選ぶ。国名で検索すると地域が見つかる。
/// 取消しても投稿画面の写真と選択中の都市はそのまま残る。
struct CityPickerView: View {
    let catalog: CityCatalog
    let selectedID: String?
    let onSelect: (City?) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var results: [City] {
        catalog.search(query, preferredCountry: locale.region?.identifier)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(nil)
                    } label: {
                        row(title: Text("photos.city.none", tableName: "Map"), subtitle: nil, selected: selectedID == nil)
                    }
                } footer: {
                    Text("photos.city.none.footer", tableName: "Map")
                }

                Section {
                    ForEach(results) { city in
                        Button {
                            choose(city)
                        } label: {
                            row(
                                title: Text(verbatim: city.name(for: locale)),
                                subtitle: city.isRegion ? nil : countryName(city.country),
                                selected: city.id == selectedID
                            )
                        }
                    }
                } footer: {
                    Text("photos.city.search.footer", tableName: "Map")
                }
            }
            .searchable(text: $query, prompt: Text("photos.city.search.prompt", tableName: "Map"))
            .navigationTitle(Text("photos.city.title", tableName: "Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("photos.city.cancel", tableName: "Map")
                    }
                }
            }
        }
    }

    private func choose(_ city: City?) {
        onSelect(city)
        dismiss()
    }

    private func countryName(_ code: String) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    private func row(title: Text, subtitle: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(RuuutoType.body(.body, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.ink)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(RuuutoPalette.sub)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(RuuutoPalette.accent)
                    .accessibilityLabel(Text("photos.city.selected", tableName: "Map"))
            }
        }
        .contentShape(Rectangle())
    }
}
