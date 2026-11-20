import SwiftUI
import SayWhatKit

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @State private var query = ""
    @State private var copiedID: UUID?

    var filtered: [HistoryItem] {
        query.isEmpty ? history.items : history.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if history.items.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "waveform",
                                           description: Text("Everything you dictate shows up here."))
                }
                ForEach(filtered) { item in
                    Button {
                        UIPasteboard.general.string = item.text
                        copiedID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.text).foregroundStyle(.primary).lineLimit(6)
                            HStack(spacing: 8) {
                                Text(item.language.uppercased()).bold().foregroundStyle(Theme.accent)
                                Text(item.date.formatted(.relative(presentation: .named)))
                                Spacer()
                                if copiedID == item.id { Label("Copied", systemImage: "checkmark").labelStyle(.titleAndIcon) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button(role: .destructive) { history.delete(item) } label: { Label("Delete", systemImage: "trash") }
                        ShareLink(item: item.text) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("History")
            .toolbar {
                if !history.items.isEmpty {
                    Menu {
                        Button("Clear all history", role: .destructive) { history.clear() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }
}

struct DictionaryView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var newWord = ""
    @State private var from = ""
    @State private var to = ""
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(settings.vocabulary, id: \.self) { Text($0) }
                        .onDelete { settings.vocabulary.remove(atOffsets: $0) }
                    HStack {
                        TextField("Name, brand or jargon (e.g. Rovera)", text: $newWord)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addWord)
                        Button("Add", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text("Vocabulary") } footer: {
                    Text("Words Whisper should know how to spell. Fed to the model as a hint.")
                }

                Section {
                    ForEach(settings.replacements) { r in
                        HStack { Text(r.from).foregroundStyle(.secondary); Image(systemName: "arrow.right").font(.caption); Text(r.to).bold() }
                    }
                    .onDelete { settings.replacements.remove(atOffsets: $0) }
                    TextField("When I say…", text: $from).textInputAutocapitalization(.never)
                    HStack {
                        TextField("…write", text: $to).textInputAutocapitalization(.never)
                        Button("Add") {
                            settings.replacements.append(Replacement(from: from, to: to)); from = ""; to = ""
                        }.disabled(from.isEmpty || to.isEmpty)
                    }
                } header: { Text("Replacements") } footer: {
                    Text("Always fix a word the same way, e.g. “chat gpt” → “ChatGPT”.")
                }

                Section {
                    ForEach(settings.snippets) { s in
                        VStack(alignment: .leading) { Text(s.trigger).bold(); Text(s.text).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    .onDelete { settings.snippets.remove(atOffsets: $0) }
                    TextField("Trigger phrase (e.g. my address)", text: $trigger).textInputAutocapitalization(.never)
                    TextField("Expands to…", text: $expansion, axis: .vertical).lineLimit(1...4)
                    Button("Add snippet") {
                        settings.snippets.append(Snippet(trigger: trigger, text: expansion)); trigger = ""; expansion = ""
                    }.disabled(trigger.isEmpty || expansion.isEmpty)
                } header: { Text("Snippets") } footer: {
                    Text("Say the trigger and Say What types the full text — emails, addresses, links, sign-offs.")
                }
            }
            .navigationTitle("Dictionary")
            .toolbar { EditButton() }
        }
    }

    private func addWord() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !settings.vocabulary.contains(w) else { return }
        settings.vocabulary.append(w)
        newWord = ""
    }
}
