import SwiftUI
import LeafReaderCore

struct VocabularyPreparationView: View {
    @Bindable var coordinator: VocabularyPreparationCoordinator
    @State private var showsFullAuditConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 620)
        .alert(
            AppText.localized("要逐一检查所有词元吗？", "Check every lemma?"),
            isPresented: $showsFullAuditConfirmation
        ) {
            Button(AppText.localized("开始完整诊断盲测", "Start Full Diagnostic Audit")) {
                coordinator.beginPredictionAudit()
            }
            Button(AppText.localized("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(AppText.localized(
                "这是用于衡量模型的诊断工具，不是 20–80 题的自适应词汇准备。它会要求你判断文档中的全部 \(coordinator.inventory?.candidates.count ?? 0) 个词元。普通学习请改用“开始 20–80 题测试”。",
                "This is a model-measurement tool, not the adaptive 20–80-question preparation. It will ask you about all \(coordinator.inventory?.candidates.count ?? 0) lemmas in this document. For normal learning, use Start 20–80 Assessment instead."
            ))
        }
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
        case .predictionAudit:
            predictionAudit
        case .predictionAuditResults:
            predictionAuditResults
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(coordinator.progressText)
                        .font(.headline)
                    Spacer()
                    Button(
                        coordinator.hasCompatiblePredictionAudit
                            ? AppText.localized("继续完整盲测", "Resume Full Audit")
                            : AppText.localized(
                                "诊断：检查全部 \(coordinator.inventory?.candidates.count ?? 0) 个词元",
                                "Diagnostic: Audit All \(coordinator.inventory?.candidates.count ?? 0) Lemmas"
                            )
                    ) {
                        if coordinator.hasCompatiblePredictionAudit {
                            coordinator.beginPredictionAudit()
                        } else {
                            showsFullAuditConfirmation = true
                        }
                    }
                    Button(AppText.localized("开始 20–80 题测试", "Start 20–80 Assessment")) {
                        coordinator.beginAssessment()
                    }
                    .buttonStyle(.borderedProminent)
                }
                HStack {
                    Spacer()
                    languagePicker
                    modePicker
                    if coordinator.experimentalDomainsEnabled {
                        domainPicker
                    }
                }
            }
            inventoryHeader
            Text(AppText.localized(
                "实验性完整盲测会跳过预备测试，并逐一显示全部 \(coordinator.inventory?.candidates.count ?? 0) 个词元（仅词元和词性）。预测在完成前保持隐藏；进度保存在本机。",
                "The experimental complete blind audit bypasses the assessment and shows all \(coordinator.inventory?.candidates.count ?? 0) lemmas using only lemma and POS. Predictions stay hidden until completion, and progress is saved locally."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
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

    private var predictionAudit: some View {
        VStack(spacing: 22) {
            HStack {
                Text(AppText.localized("盲测", "Blind prediction audit") + " " + coordinator.predictionAuditProgressText)
                    .font(.headline)
                Spacer()
                Button(AppText.localized("返回清单", "Back to inventory")) {
                    coordinator.returnToInventoryFromPredictionAudit()
                }
            }
            Text(AppText.localized(
                "在作答前不显示模型预测、释义或文档上下文。请选择你现在能否从词元和词性中想起文档相关含义。",
                "The model prediction, definition, and document context stay hidden. Answer whether you can currently retrieve the document-relevant meaning from the lemma and POS."
            ))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 640)
            if let item = coordinator.currentPredictionAuditItem {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.displayLemma)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                    partOfSpeech(item.partOfSpeech)
                }
                HStack(spacing: 12) {
                    Button(AppText.localized("认识", "Know")) {
                        coordinator.recordPredictionAudit(.known)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(AppText.localized("不认识", "Don’t know")) {
                        coordinator.recordPredictionAudit(.unknown)
                    }
                }
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(28)
    }

    private var predictionAuditResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let result = coordinator.predictionAuditResult {
                Text(AppText.localized("个人盲测结果", "Personal blind-audit result"))
                    .font(.title2.weight(.semibold))
                Text(AppText.localized(
                    "这是对一位读者和一份文档的完整自报检查，不是独立评分的含义回忆测试，也不能验证所有学习者。",
                    "This is a complete self-report check for one reader and one document. It is not independently scored meaning recall and does not validate the model for other learners."
                ))
                .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    auditMetric(
                        AppText.localized("预测学习清单精确率", "Predicted-list precision"),
                        result.predictedLearningPrecision
                    )
                    auditMetric(
                        AppText.localized("预测学习清单召回率", "Predicted-list recall"),
                        result.predictedLearningRecall
                    )
                    auditMetric(
                        AppText.localized("当前可评估词汇词元覆盖率", "Current assessable lexical-token coverage"),
                        result.currentLexicalTokenCoverage
                    )
                    auditMetric(
                        AppText.localized("掌握所选词后的可评估投影覆盖率", "Projected assessable coverage after mastering selected words"),
                        result.projectedLexicalTokenCoverage
                    )
                    auditMetric(AppText.localized("Brier 分数", "Brier score"), result.brierScore, percent: false)
                    auditMetric(
                        AppText.localized("10 桶 ECE", "Ten-bin ECE"),
                        result.expectedCalibrationError,
                        percent: false
                    )
                }
                Text(AppText.localized(
                    "模型遗漏的生词：\(result.missedUnknownCount) · 实际生词：\(result.actualUnknownCount) · 预测学习词：\(result.predictedLearningCount)",
                    "Missed unknown lemmas: \(result.missedUnknownCount) · actual unknown lemmas: \(result.actualUnknownCount) · predicted learning lemmas: \(result.predictedLearningCount)"
                ))
                .font(.headline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            result.scoredItems.filter {
                                $0.item.selectedForLearning || $0.answer == .unknown
                            },
                            id: \.item.canonicalKey
                        ) { scored in
                            HStack {
                                Text(scored.item.displayLemma).font(.body.weight(.semibold))
                                partOfSpeech(scored.item.partOfSpeech)
                                Spacer()
                                Text(scored.item.selectedForLearning
                                    ? AppText.localized("模型选入", "Selected by model")
                                    : AppText.localized("模型遗漏", "Missed by model"))
                                    .foregroundStyle(
                                        scored.item.selectedForLearning ? Color.secondary : Color.red
                                    )
                                Text(scored.answer == .known
                                    ? AppText.localized("实际认识", "Actually known")
                                    : AppText.localized("实际不认识", "Actually unknown"))
                                    .foregroundStyle(
                                        scored.answer == .known ? Color.orange : Color.secondary
                                    )
                                Text("P(known) \(scored.item.predictedKnownProbability * 100, specifier: "%.0f")%")
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(AppText.localized("返回清单", "Back to inventory")) {
                        coordinator.returnToInventoryFromPredictionAudit()
                    }
                    Button(AppText.localized("重新盲测", "Restart audit"), role: .destructive) {
                        coordinator.resetPredictionAudit()
                        coordinator.beginPredictionAudit()
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func auditMetric(_ label: String, _ value: Double, percent: Bool = true) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(percent ? "\(value * 100, specifier: "%.1f")%" : "\(value, specifier: "%.4f")")
                .monospacedDigit()
        }
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
                if coordinator.isPreparingNextQuestion {
                    ProgressView(AppText.localized("正在准备下一个词…", "Preparing the next word…"))
                } else {
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
                }
            case .learningAfterAnswer:
                if coordinator.isPreparingNextQuestion {
                    ProgressView(AppText.localized("正在准备下一个词…", "Preparing the next word…"))
                } else {
                    Button(AppText.localized("继续", "Continue")) { coordinator.continueAfterLearning() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
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
        partOfSpeech(candidate.partOfSpeech)
    }

    @ViewBuilder
    private func partOfSpeech(_ partOfSpeech: VocabularyPartOfSpeech) -> some View {
        if let label = partOfSpeech.displayName {
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
