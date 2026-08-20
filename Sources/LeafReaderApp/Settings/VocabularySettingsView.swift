import SwiftUI
import LeafReaderCore

struct VocabularySettingsView: View {
    @Bindable var model: VocabularySettingsModel

    var body: some View {
        Form {
            Section(AppText.localized("跨书词汇适应", "Cross-book vocabulary adaptation")) {
                Text(AppText.localized(
                    "默认仅在本机复用已完成测试中的答案。阅读暴露、词典查询和文档内容不会进入此资料。",
                    "Enabled locally by default. Only evidence from completed assessments is reused; reading exposure, dictionary lookups, and document content are excluded."
                ))
                .foregroundStyle(.secondary)

                if model.isLoading && model.summaries.isEmpty {
                    ProgressView()
                } else if model.summaries.isEmpty {
                    Text(AppText.localized("尚无英语或德语读者资料。", "No English or German reader profile yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.summaries, id: \.languageCode) { summary in
                        LabeledContent(languageName(summary.languageCode)) {
                            HStack(spacing: 12) {
                                Text(AppText.localized(
                                    "\(summary.completedSessionCount) 次测试 · \(summary.verifiedEvidenceCount) 个已核对答案 · \(summary.lastUpdatedAt.formatted(date: .abbreviated, time: .omitted))",
                                    "\(summary.completedSessionCount) sessions · \(summary.verifiedEvidenceCount) verified answers · \(summary.lastUpdatedAt.formatted(date: .abbreviated, time: .omitted))"
                                ))
                                .foregroundStyle(.secondary)
                                Button(AppText.localized("重置", "Reset"), role: .destructive) {
                                    model.reset(languageCode: summary.languageCode)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text(AppText.localized(
                    "暖启动仅在资料不超过 180 天、至少来自 2 次完成的测试且包含 40 个已核对答案时启用。新文档仍会直接验证两个高置信度预测。",
                    "Warm start is used only when the profile is at most 180 days old, covers at least two completed sessions and 40 verified answers, and the new document directly validates two tail predictions."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(AppText.localized("研究数据导出", "Research data export")) {
                Text(AppText.localized(
                    "仅在您明确保存时生成本地 JSON 文件。不会自动上传。导出不含文档标题、ID、路径、上下文、释义、输入的含义、精确时间或账户信息。",
                    "A local JSON file is created only when you explicitly save it. Nothing is uploaded automatically. The export excludes document titles, IDs, paths, contexts, definitions, typed meanings, exact timestamps, and account data."
                ))
                .foregroundStyle(.secondary)
                LabeledContent(AppText.localized("参与者假名", "Participant pseudonym")) {
                    Text(model.participantPseudonym).textSelection(.enabled).monospaced()
                    Button(AppText.localized("重置", "Reset")) { model.resetPseudonym() }
                }
                TextField(AppText.localized("第一语言代码（可选）", "L1 language code (optional)"), text: $model.firstLanguageCode)
                TextField(AppText.localized("自评水平（可选）", "Broad self-rated proficiency (optional)"), text: $model.selfRatedProficiency)
                LabeledContent(AppText.localized("记录", "Records"), value: "\(model.researchRecordCount)")
                HStack {
                    Button(AppText.localized("预览字段", "Preview included fields")) { model.previewResearchExport() }
                    Button(AppText.localized("保存研究导出…", "Save research export…")) { model.saveResearchExport() }
                        .disabled(model.researchRecordCount == 0)
                }
                if !model.researchPreview.isEmpty {
                    ScrollView {
                        Text(model.researchPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
                if let error = model.exportError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .settingsFormStyle()
    }

    private func languageName(_ code: String) -> String {
        switch code {
        case "en": AppText.localized("英语", "English")
        case "de": AppText.localized("德语", "German")
        default: code
        }
    }
}
