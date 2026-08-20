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
                    "概率是基于词频和本次测试的模型估计；98% 指词汇覆盖率，并非理解保证。",
                    "Probabilities are frequency-based estimates from this assessment; 98% means lexical coverage, not guaranteed comprehension."
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
                "先分析本文档的英语或德语词汇，再用通常 20–80 个核对问题建立学习列表；符合条件的本地资料最少可用 8 题。",
                "Analyze this document’s English or German vocabulary, then build a list with usually 20–80 verified questions; an eligible local profile may reduce the minimum to 8."
            ))
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 600)
            languagePicker
            modePicker
            if coordinator.experimentalDomainsEnabled {
                domainPicker
            }
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
                if coordinator.experimentalDomainsEnabled {
                    domainPicker
                }
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
                HStack(spacing: 6) {
                    Text(candidate.displayLemma).font(.body.weight(.semibold))
                    partOfSpeech(candidate)
                }
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
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(candidate.displayLemma)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                    partOfSpeech(candidate)
                }
                if coordinator.interactionState == .awaitingAnswer {
                    Toggle(
                        AppText.localized("输入含义再核对（可选）", "Type a meaning before checking (optional)"),
                        isOn: $coordinator.typedModeEnabled
                    )
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: 420, alignment: .leading)
                    if coordinator.typedModeEnabled {
                        TextField(
                            AppText.localized("用自己的话写下含义", "Meaning in your own words"),
                            text: $coordinator.typedMeaningDraft,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                    }
                }
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
            HStack(spacing: 10) {
                Button(AppText.localized("我认识", "I know it")) { coordinator.chooseKnown() }
                    .buttonStyle(.borderedProminent)
                Button(AppText.localized("不确定", "Not sure")) { coordinator.chooseUnsure() }
                Button(AppText.localized("我不认识", "I don’t know")) { coordinator.chooseReportedUnknown() }
                Button(AppText.localized("不是单词/是名称", "Not a word/name")) {
                    coordinator.excludeCurrentCandidate()
                }
            }
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
                    if !coordinator.typedMeaningDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider()
                        Text(AppText.localized("你的回答", "Your answer"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(coordinator.typedMeaningDraft)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            switch coordinator.interactionState {
            case .pendingKnownVerification:
                HStack(spacing: 10) {
                    Button(AppText.localized("我的含义正确", "My meaning was correct")) {
                        coordinator.verifyKnown(correct: true)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(AppText.localized("不正确/只对了一部分", "No / only partly")) {
                        coordinator.verifyKnown(correct: false)
                    }
                }
                .controlSize(.large)
            case .learningAfterAnswer:
                Button(AppText.localized("继续", "Continue")) { coordinator.continueAfterLearning() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .awaitingAnswer:
                EmptyView()
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = coordinator.results {
                let uncertainty = String(format: "%.1f", result.residualUncertainty)
                let coverage = String(format: "%.1f", result.expectedCoverageAfterSelection * 100)
                let lowerCoverage = String(
                    format: "%.1f",
                    result.diagnostics.conservativeCoverageLowerBound * 100
                )
                Text(AppText.localized(
                    "已回答 \(result.answeredQuestionCount) 题 · \(stopReasonText(result.diagnostics.stopReason)) · 剩余不确定度 \(uncertainty) · 预计覆盖率 \(coverage)%（后验预测第 5 百分位 \(lowerCoverage)%）",
                    "\(result.answeredQuestionCount) answered · \(stopReasonText(result.diagnostics.stopReason)) · residual uncertainty \(uncertainty) · expected coverage \(coverage)% (posterior-predictive 5th percentile \(lowerCoverage)%)"
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
                    HStack(spacing: 6) {
                        Text(item.candidate.displayLemma).font(.body.weight(.semibold))
                        partOfSpeech(item.candidate)
                    }
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
                Text("Estimated P(known) \(item.knownProbability * 100, specifier: "%.0f")%")
                    .monospacedDigit()
                    .foregroundStyle(item.classification == .uncertain ? .orange : .secondary)
            }
            Text("×\(item.candidate.occurrenceCount)")
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func partOfSpeech(_ candidate: DocumentVocabularyCandidate) -> some View {
        if let label = candidate.partOfSpeech.displayName {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
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

    private var domainPicker: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Picker(
                AppText.localized("实验领域", "Experimental domain"),
                selection: Binding(
                    get: { coordinator.selectedDocumentDomain },
                    set: { coordinator.selectDocumentDomain($0) }
                )
            ) {
                Text(AppText.localized("通用", "General")).tag(VocabularyDocumentDomain.general)
                Text(AppText.localized("文学", "Literary")).tag(VocabularyDocumentDomain.literary)
                Text(AppText.localized("新闻", "News")).tag(VocabularyDocumentDomain.news)
                Text(AppText.localized("技术/参考", "Technical/reference"))
                    .tag(VocabularyDocumentDomain.technicalReference)
            }
            .frame(width: 190)
            Text(AppText.localized("仅记录元数据；不改变生产难度", "Metadata only; production difficulty unchanged"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
        case .verifiedKnown: AppText.localized("已核对认识", "Verified known")
        case .reportedUnknown: AppText.localized("自报不认识", "Reported unknown")
        case .notSure: AppText.localized("不确定", "Not sure")
        case .estimatedKnown: AppText.localized("估计认识", "Estimated known")
        case .uncertain: AppText.localized("不确定", "Uncertain")
        case .estimatedUnknown: AppText.localized("估计不认识", "Estimated unknown")
        case .excluded: AppText.localized("已排除", "Excluded")
        }
    }

    private func stopReasonText(_ reason: VocabularyAssessmentStopReason?) -> String {
        switch reason {
        case .exhaustedCandidates:
            AppText.localized("已测试所有可回答词", "all answerable words assessed")
        case .lowExpectedValue:
            AppText.localized("继续提问的预期收益很低", "additional questions have low expected value")
        case .targetCoverageStable:
            AppText.localized("覆盖率目标已稳定", "coverage target is stable")
        case .questionLimit:
            AppText.localized("已达到 80 题上限，仍有不确定性", "80-question limit reached with residual uncertainty")
        case nil:
            AppText.localized("模型估计", "model estimate")
        }
    }
}
