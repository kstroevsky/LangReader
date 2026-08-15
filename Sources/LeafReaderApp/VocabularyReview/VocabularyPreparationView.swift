import SwiftUI
import LeafReaderCore

struct VocabularyPreparationView: View {
    @Bindable var coordinator: VocabularyPreparationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppText.localized("阅读前词汇准备", "Prepare Vocabulary"))
                    .font(.title2.weight(.semibold))
                Text(AppText.localized(
                    "估计结果包含不确定性；98% 指词汇覆盖率，并非理解保证。",
                    "Results are probabilistic; 98% means lexical coverage, not guaranteed comprehension."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .welcome:
            welcome
        case .analyzing:
            progress
        case .inventory:
            inventory
        case .assessment:
            assessment
        case .results:
            results
        case .importing:
            progress
        case let .error(message):
            error(message)
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(AppText.localized(
                "先分析本文档的英语或德语词汇，再用 20–80 个自评问题建立学习列表。",
                "Analyze this document’s English or German vocabulary, then build a learning list with 20–80 self-scored questions."
            ))
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 600)
            languagePicker
            modePicker
            Button(AppText.localized("分析文档", "Analyze Document")) {
                coordinator.startAnalysis()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding(32)
    }

    private var progress: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(coordinator.progressText)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(coordinator.progressText)
                    .font(.headline)
                Spacer()
                languagePicker
                modePicker
                Button(AppText.localized("开始测试", "Start Assessment")) {
                    coordinator.beginAssessment()
                }
                .buttonStyle(.borderedProminent)
            }
            inventoryHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(coordinator.inventory?.candidates ?? []) { candidate in
                        inventoryRow(candidate)
                        Divider()
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }

    private var inventoryHeader: some View {
        HStack {
            Text(AppText.localized("词元与词形", "Lemma and forms")).frame(maxWidth: .infinity, alignment: .leading)
            Text(AppText.localized("文档次数", "Document count")).frame(width: 110, alignment: .trailing)
            Text(AppText.localized("通用排名", "General rank")).frame(width: 110, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private func inventoryRow(_ candidate: DocumentVocabularyCandidate) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayLemma).font(.body.weight(.semibold))
                Text(candidate.observedForms.map { "\($0.surface) ×\($0.occurrenceCount)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(candidate.occurrenceCount)").frame(width: 110, alignment: .trailing)
            Text(candidate.generalFrequencyRank.map(String.init) ?? "—").frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var assessment: some View {
        VStack(spacing: 18) {
            HStack {
                Text(AppText.localized("问题", "Question") + " " + coordinator.questionLimitText)
                    .font(.headline)
                Spacer()
                if coordinator.hasSavedAnswers {
                    Button(AppText.localized("重新开始", "Start Over")) { coordinator.resetAssessment() }
                }
            }
            if let candidate = coordinator.currentCandidate {
                Text(candidate.displayLemma)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .textSelection(.enabled)
                definition(candidate)
            }
            Spacer(minLength: 8)
        }
        .padding(28)
    }

    @ViewBuilder
    private func definition(_ candidate: DocumentVocabularyCandidate) -> some View {
        switch coordinator.definitionState {
        case .hidden:
            Button(AppText.localized("显示释义", "Reveal")) { coordinator.revealCurrentQuestion() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .loading:
            ProgressView(AppText.localized("正在查询释义…", "Looking up definition…"))
        case let .unavailable(message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary)
                HStack {
                    Button(AppText.localized("重试", "Retry")) { coordinator.retryDefinition() }
                    Button(AppText.localized("跳过", "Skip")) { coordinator.skipDefinition() }
                }
            }
        case let .available(definition):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(candidate.observedForms.map { "\($0.surface) ×\($0.occurrenceCount)" }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !coordinator.currentContext.isEmpty {
                        Text(coordinator.currentContext)
                            .font(.body.italic())
                            .padding(10)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text(definition)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            HStack(spacing: 10) {
                Button(AppText.localized("认识", "Knew it")) { coordinator.score(.known) }
                    .buttonStyle(.borderedProminent)
                Button(AppText.localized("不认识", "Didn’t know")) { coordinator.score(.unknown) }
                Button(AppText.localized("不确定", "Wasn’t sure")) { coordinator.score(.unknown) }
                Button(AppText.localized("不是单词/是名称", "Not a word/name")) { coordinator.excludeCurrentCandidate() }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = coordinator.results {
                let uncertainty = String(format: "%.1f", result.residualUncertainty)
                let coverage = String(format: "%.1f", result.expectedCoverageAfterSelection * 100)
                Text(AppText.localized(
                    "已回答 \(result.answeredQuestionCount) 题 · 剩余不确定度 \(uncertainty) · 预计覆盖率 \(coverage)%",
                    "\(result.answeredQuestionCount) answered · residual uncertainty \(uncertainty) · expected coverage \(coverage)%"
                ))
                .font(.headline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(result.items) { item in
                            resultRow(item)
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(AppText.localized("重新测试", "Retake")) { coordinator.resetAssessment() }
                    Text(AppText.localized(
                        "推断词不会标记为已确认；可在创建前编辑每一项。",
                        "Inferred words are not marked as confirmed; edit every selection before creating records."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(AppText.localized("创建并复习", "Create & Review")) {
                        coordinator.createAndReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.selectedKeys.isEmpty)
                }
            }
        }
        .padding(20)
    }

    private func resultRow(_ item: VocabularyAssessmentResultItem) -> some View {
        let alreadySaved = coordinator.alreadySavedKeys.contains(item.id)
        return HStack {
            Toggle(isOn: Binding(
                get: { coordinator.selectedKeys.contains(item.id) },
                set: { coordinator.updateSelection(item.id, selected: $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.candidate.displayLemma).font(.body.weight(.semibold))
                    Text(classificationText(item.classification))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(alreadySaved || item.classification == .excluded)
            Spacer()
            if alreadySaved {
                Text(AppText.localized("已在词库", "Already in library"))
                    .foregroundStyle(.secondary)
            } else {
                Text("P(known) \(item.knownProbability * 100, specifier: "%.0f")%")
                    .monospacedDigit()
                    .foregroundStyle(item.classification == .uncertain ? .orange : .secondary)
            }
            Text("×\(item.candidate.occurrenceCount)")
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var modePicker: some View {
        Picker(AppText.localized("目标", "Goal"), selection: Binding(
            get: { coordinator.mode == .allUnknown ? 0 : 1 },
            set: { coordinator.mode = $0 == 0 ? .allUnknown : .targetCoverage(0.98) }
        )) {
            Text(AppText.localized("估计全部生词", "Estimate all unknown")).tag(0)
            Text(AppText.localized("达到 98% 覆盖率", "Target 98% coverage")).tag(1)
        }
        .pickerStyle(.segmented)
        .frame(width: 330)
    }

    private var languagePicker: some View {
        Picker(AppText.localized("语言", "Language"), selection: $coordinator.selectedLanguageCode) {
            Text(AppText.localized("自动检测", "Auto-detect")).tag("auto")
            Text("English").tag("en")
            Text("Deutsch").tag("de")
        }
        .frame(width: 150)
    }

    private func error(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Button(AppText.localized("重试", "Retry")) { coordinator.startAnalysis() }
            Spacer()
        }
        .padding(32)
    }

    private func classificationText(_ classification: VocabularyAssessmentClassification) -> String {
        switch classification {
        case .confirmedKnown: AppText.localized("确认认识", "Confirmed known")
        case .confirmedUnknown: AppText.localized("确认不认识", "Confirmed unknown")
        case .probablyKnown: AppText.localized("可能认识", "Probably known")
        case .uncertain: AppText.localized("不确定", "Uncertain")
        case .probablyUnknown: AppText.localized("可能不认识", "Probably unknown")
        case .excluded: AppText.localized("已排除", "Excluded")
        }
    }
}
